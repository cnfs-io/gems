# frozen_string_literal: true

require "erb"
require "pathname"

module Pcs
  class PveHost < Host
    sti_type "proxmox"

    after_initialize :apply_class_defaults

    INTERFACES_TEMPLATE = Pathname.new(__dir__).join("..", "..", "templates", "pve", "interfaces.erb")

    def self.detect?(ssh)
      result = ssh.exec!("command -v pveversion")
      !result.nil? && result.include?("pveversion")
    rescue StandardError
      false
    end

    def render(output_dir)
      write_local(output_dir, "/etc/network/interfaces", render_interfaces)
      write_local(output_dir, "/etc/hosts", render_hosts)
      pub_key = site.ssh_public_key_content
      write_local(output_dir, "/root/.ssh/authorized_keys", pub_key + "\n") if pub_key
    end

    def deploy!(output_dir, state:)
      with_ssh_probe(state: state) do |ssh|
        ssh.exec!("cp /etc/network/interfaces /etc/network/interfaces.bak")
        push_file(ssh, output_dir, "/etc/network/interfaces")
        push_file(ssh, output_dir, "/etc/hosts")
        push_ssh_key(ssh, output_dir)
        ssh.exec!("hostnamectl set-hostname #{fqdn}")
        restart_networking(ssh)
      end
    end

    def configure!
      # Post-provision: cluster join handled by cluster service
    end

    def healthy?
      with_ssh(user: "root", state: Pcs::State.load) do |ssh|
        result = ssh.exec!("pveversion")
        !result.nil? && result.include?("pve-manager")
      end
    rescue StandardError
      false
    end

    def rendered_interfaces(**opts)
      render_interfaces(**opts)
    end

    private

    def apply_class_defaults
      self.preseed_interface ||= Pcs.config.service.proxmox.default_preseed_interface
      self.preseed_device ||= Pcs.config.service.proxmox.default_preseed_device
    end

    def render_interfaces(physical_ifaces: nil)
      all_ifaces = physical_ifaces || default_physical_interfaces
      servers_iface = all_ifaces.first || "enp1s0"
      remaining = all_ifaces.drop(1)

      storage = interface_on(:storage)
      storage_iface = storage ? remaining.shift : nil
      extra_ifaces = remaining

      vars = {
        servers_iface: servers_iface,
        servers_ip: ip_on(:compute),
        servers_prefix: compute_network.subnet.split("/").last,
        servers_gateway: compute_network.gateway,
        dns_resolvers: compute_network.dns_resolvers || [],
        domain: site.domain,
        storage_iface: storage_iface,
        storage_ip: storage ? ip_on(:storage) : nil,
        storage_prefix: storage ? storage_network.subnet.split("/").last : nil,
        extra_ifaces: extra_ifaces
      }

      ERB.new(INTERFACES_TEMPLATE.read, trim_mode: "-").result_with_hash(**vars)
    end

    def render_hosts(inventory: nil)
      lines = ["127.0.0.1 localhost"]
      lines << "#{ip_on(:compute)} #{fqdn} #{hostname}"

      if inventory
        Pcs::Host.hosts_of_type("proxmox").each do |peer|
          next if peer.hostname == hostname
          lines << "#{peer.ip_on(:compute)} #{peer.fqdn} #{peer.hostname}"
        end

        Pcs::Host.hosts_of_type("truenas").each do |nas|
          lines << "#{nas.ip_on(:compute)} #{nas.fqdn} #{nas.hostname}"
        end
      end

      lines.join("\n") + "\n"
    end

    def default_physical_interfaces
      ifaces = ["enp1s0"]
      ifaces << "enp2s0" if interface_on(:storage)
      ifaces
    end

    def push_file(ssh, output_dir, remote_path)
      content = (output_dir / remote_path.delete_prefix("/")).read
      ssh.exec!("cat > #{remote_path} <<'EOF'\n#{content}EOF")
    end

    def push_ssh_key(ssh, output_dir)
      pub_key = (output_dir / "root/.ssh/authorized_keys").read.strip
      ssh.exec!("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
      ssh.exec!("echo '#{pub_key}' >> /root/.ssh/authorized_keys")
      ssh.exec!("chmod 600 /root/.ssh/authorized_keys")
    end

    def restart_networking(ssh)
      if ssh.exec!("command -v ifreload")&.include?("ifreload")
        ssh.exec!("ifreload -a")
      else
        ssh.exec!("systemctl restart networking")
      end
    end
  end
end
