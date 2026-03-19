# frozen_string_literal: true

module Pcs1
  class PveHost < Host
    sti_type "proxmox"

    attribute :pve_status, :string, default: "pending"

    # --- Proxmox-specific state machine ---

    state_machine :pve_status, initial: :pending do
      state :pending
      state :pve_installed
      state :networks_validated
      state :clustered

      event :install_pve do
        transition pending: :pve_installed, if: :pve_install_verified?
      end

      event :validate_networks do
        transition pve_installed: :networks_validated, if: :networks_valid?
      end

      event :join_cluster do
        transition networks_validated: :clustered
      end
    end

    # --- PVE installation ---

    def install_pve!
      raise "Host must be provisioned first" unless status == "provisioned"

      target_ip = interfaces.first&.configured_ip
      raise "No configured IP" unless target_ip

      Pcs1.logger.info("Installing Proxmox VE on #{hostname} (#{target_ip})...")

      script = render_script("proxmox/install.sh.erb", install_vars)
      run_remote_script!(target_ip, script)

      Pcs1.logger.info("Rebooting #{hostname}...")
      begin
        ssh_exec!("reboot")
      rescue StandardError
        # Expected — SSH drops on reboot
      end

      Pcs1.logger.info("Waiting for PVE to come back...")
      wait_for_host(target_ip)

      if pve_install_verified?
        fire_pve_status_event(:install_pve)
        save!
        Pcs1.logger.info("Proxmox VE installed on #{hostname}.")
      else
        raise "PVE installation verification failed on #{hostname}"
      end
    end

    # --- Cluster operations ---

    def create_cluster!(cluster_name: nil)
      raise "PVE must be installed first" unless %w[pve_installed networks_validated].include?(pve_status)

      target_ip = interfaces.first&.configured_ip
      cluster_name ||= site&.name || "pve"

      Pcs1.logger.info("Creating cluster '#{cluster_name}' on #{hostname}...")
      script = render_script("proxmox/create-cluster.sh.erb", { cluster_name: cluster_name })
      run_remote_script!(target_ip, script)

      fire_pve_status_event(:join_cluster)
      save!
      Pcs1.logger.info("Cluster '#{cluster_name}' created on #{hostname}.")
    end

    def join_cluster!(master_host:)
      raise "PVE must be installed first" unless %w[pve_installed networks_validated].include?(pve_status)

      target_ip = interfaces.first&.configured_ip
      master_ip = master_host.interfaces.first&.configured_ip
      raise "Master host has no configured IP" unless master_ip

      Pcs1.logger.info("Joining #{hostname} to cluster via #{master_ip}...")
      script = render_script("proxmox/join-cluster.sh.erb", { master_ip: master_ip })
      run_remote_script!(target_ip, script)

      fire_pve_status_event(:join_cluster)
      save!
      Pcs1.logger.info("#{hostname} joined cluster via #{master_ip}.")
    end

    # --- Guards ---

    def pve_install_verified?
      target_ip = interfaces.first&.configured_ip
      return false unless target_ip

      user = connect_user
      return false unless user

      Net::SSH.start(target_ip, user,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        result = ssh.exec!("pveversion 2>/dev/null")
        !result.nil? && result.include?("pve-manager")
      end
    rescue StandardError
      false
    end

    def networks_valid?
      # TODO: verify compute and storage bridges are configured
      key_access?(target: :configured_ip)
    end

    # --- Detection ---

    def self.detect?(ssh)
      result = ssh.exec!("pveversion 2>/dev/null")
      !result.nil? && result.include?("pve-manager")
    rescue StandardError
      false
    end

    def restart_networking!
      Pcs1.logger.info("Restarting networking on #{hostname || id}...")
      ssh_exec!("ifreload -a 2>/dev/null || systemctl restart networking")
    rescue StandardError
      Pcs1.logger.warn("Networking restart failed, rebooting...")
      begin
        ssh_exec!("reboot")
      rescue StandardError
        # Expected
      end
    end

    private

    def install_vars
      domain = site&.domain || "local"
      {
        hostname: hostname,
        domain: domain,
        fqdn: "#{hostname}.#{domain}",
        codename: "trixie",
        hosts_content: build_hosts_file
      }
    end

    def build_hosts_file
      domain = site&.domain || "local"
      target_ip = interfaces.first&.configured_ip

      lines = ["127.0.0.1 localhost"]
      lines << "#{target_ip} #{hostname}.#{domain} #{hostname}"

      site&.hosts&.each do |peer|
        next if peer.id == self.id
        next unless peer.type == "proxmox" && peer.hostname

        peer_ip = peer.interfaces.first&.configured_ip
        next unless peer_ip

        lines << "#{peer_ip} #{peer.hostname}.#{domain} #{peer.hostname}"
      end

      lines.join("\n") + "\n"
    end

    def render_script(relative_path, vars)
      template_path = Pcs1.resolve_template(relative_path)
      template = ERB.new(template_path.read, trim_mode: "-")
      template.result_with_hash(**vars)
    end

    def run_remote_script!(target_ip, script_content)
      user = connect_user
      raise "No connect_user for host #{hostname || id}" unless user

      Net::SSH.start(target_ip, user,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        ssh.exec!("cat > /tmp/pcs-script.sh <<'SCRIPT'\n#{script_content}SCRIPT")
        ssh.exec!("chmod +x /tmp/pcs-script.sh")
        output = ssh.exec!("bash /tmp/pcs-script.sh 2>&1")
        Pcs1.logger.info(output) if output && !output.strip.empty?
        ssh.exec!("rm -f /tmp/pcs-script.sh")
      end
    end
  end
end
