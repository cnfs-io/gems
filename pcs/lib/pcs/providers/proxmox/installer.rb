# frozen_string_literal: true

module Pcs
  module Providers
    module Proxmox
      class Installer
        attr_reader :host, :site, :state

        def initialize(host:, site:, state:)
          @host = host
          @site = site
          @state = state
        end

        def install!
          if check_already_installed
            puts "  -> PVE already installed, verifying..."
            verify
            return
          end

          configure_hostname
          add_proxmox_repo
          install_packages
          enable_iscsi
          configure_network
          reboot_and_wait
          verify
        end

        private

        def hostname       = host.hostname
        def compute_ip     = host.ip_on(:compute)
        def domain         = site.domain
        def fqdn           = "#{hostname}.#{domain}"
        def proxmox_config = Pcs.config.service.proxmox

        def ssh_to_discovered(&block)
          Adapters::SSH.connect(
            host: host.discovered_ip,
            key: site.ssh_private_key_path,
            user: "root",
            &block
          )
        end

        def ssh_to_compute(&block)
          Adapters::SSH.connect(
            host: compute_ip,
            key: site.ssh_private_key_path,
            user: "root",
            &block
          )
        end

        # Step 1: Check if PVE is already installed
        def check_already_installed
          ssh_to_discovered do |ssh|
            result = ssh.exec!("command -v pveversion")
            return !result.nil? && result.include?("pveversion")
          end
        rescue StandardError
          false
        end

        # Step 2: Set hostname + write /etc/hosts with all peers
        def configure_hostname
          puts "  -> Configuring hostname: #{fqdn}"
          hosts_content = build_hosts_file

          ssh_to_discovered do |ssh|
            ssh.exec!("hostnamectl set-hostname #{fqdn}")
            ssh.exec!("cat > /etc/hosts <<'HOSTS'\n#{hosts_content}HOSTS")
          end
        end

        # Step 3: Add Proxmox VE apt repository
        def add_proxmox_repo
          puts "  -> Adding Proxmox VE repository"

          ssh_to_discovered do |ssh|
            # Add Proxmox GPG key
            ssh.exec!("wget -qO /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg " \
                       "http://download.proxmox.com/debian/proxmox-release-bookworm.gpg 2>/dev/null || " \
                       "wget -qO /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg " \
                       "http://download.proxmox.com/debian/proxmox-release-trixie.gpg 2>/dev/null || true")

            # Add no-subscription repo (detect Debian codename)
            codename = ssh.exec!("lsb_release -cs 2>/dev/null || cat /etc/os-release | grep VERSION_CODENAME | cut -d= -f2")&.strip
            codename = "trixie" if codename.nil? || codename.empty?

            ssh.exec!("cat > /etc/apt/sources.list.d/pve-no-subscription.list <<'EOF'\n" \
                       "deb http://download.proxmox.com/debian/pve #{codename} pve-no-subscription\nEOF")

            # Disable enterprise repo if it exists
            ssh.exec!("rm -f /etc/apt/sources.list.d/pve-enterprise.list")
            ssh.exec!("rm -f /etc/apt/sources.list.d/ceph.list")
          end
        end

        # Step 4: Install PVE packages
        def install_packages
          puts "  -> Installing Proxmox VE packages (this takes a while)..."

          # Transition state to installing
          state.update_host(hostname, "installing")
          state.save!

          ssh_to_discovered do |ssh|
            # Pre-configure postfix to avoid interactive prompts
            ssh.exec!("echo 'postfix postfix/mailname string #{fqdn}' | debconf-set-selections")
            ssh.exec!("echo 'postfix postfix/main_mailer_type string \"Local only\"' | debconf-set-selections")

            # Update and install
            ssh.exec!("apt-get update -y")
            ssh.exec!("DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y")
            ssh.exec!("DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi chrony")

            # Remove old kernel if present
            ssh.exec!("apt-get remove -y linux-image-amd64 'linux-image-6.1*' 2>/dev/null || true")
            ssh.exec!("update-grub")
          end
        end

        # Step 5: Enable iSCSI services
        def enable_iscsi
          puts "  -> Enabling iSCSI services"

          ssh_to_discovered do |ssh|
            ssh.exec!("systemctl enable --now open-iscsi iscsid")
          end
        end

        # Step 6: Configure network interfaces — host IS the STI model
        def configure_network
          puts "  -> Configuring network interfaces"

          interfaces_content = host.rendered_interfaces

          ssh_to_discovered do |ssh|
            ssh.exec!("cp /etc/network/interfaces /etc/network/interfaces.pre-pve")
            ssh.exec!("cat > /etc/network/interfaces <<'EOF'\n#{interfaces_content}EOF")
          end
        end

        # Step 7: Reboot and wait for PVE web UI on compute_ip
        def reboot_and_wait
          puts "  -> Rebooting node..."

          ssh_to_discovered do |ssh|
            ssh.exec!("nohup reboot &>/dev/null &")
          end
        rescue StandardError
          # Expected — SSH connection drops on reboot
        ensure
          cfg = proxmox_config
          puts "  -> Waiting #{cfg.reboot_initial_wait}s for reboot..."
          sleep cfg.reboot_initial_wait

          puts "  -> Polling #{compute_ip}:#{cfg.web_port}..."
          cfg.reboot_max_attempts.times do |i|
            if Adapters::SSH.port_open?(compute_ip, cfg.web_port, 5)
              puts "  -> PVE web UI is up on #{compute_ip}:#{cfg.web_port}"
              return
            end
            puts "  -> Attempt #{i + 1}/#{cfg.reboot_max_attempts} — not yet reachable"
            sleep cfg.reboot_poll_interval
          end

          raise "Node #{hostname} did not come back on #{compute_ip}:#{cfg.web_port} after reboot"
        end

        # Step 8: Verify PVE installation
        def verify
          puts "  -> Verifying PVE installation on #{compute_ip}..."

          ssh_to_compute do |ssh|
            result = ssh.exec!("pveversion")
            unless result&.include?("pve-manager")
              raise "PVE verification failed — pveversion returned: #{result}"
            end

            puts "  -> Verified: #{result.strip}"
          end

          state.update_host(hostname, "provisioned")
          state.save!
        end

        def build_hosts_file
          lines = ["127.0.0.1 localhost"]
          lines << "#{compute_ip} #{fqdn} #{hostname}"

          # Add all proxmox peers
          Pcs::Host.hosts_of_type("proxmox").each do |peer|
            next if peer.hostname == hostname

            peer_fqdn = "#{peer.hostname}.#{domain}"
            lines << "#{peer.ip_on(:compute)} #{peer_fqdn} #{peer.hostname}"
          end

          # Add NAS hosts
          Pcs::Host.hosts_of_type("truenas").each do |nas|
            nas_fqdn = "#{nas.hostname}.#{domain}"
            lines << "#{nas.ip_on(:compute)} #{nas_fqdn} #{nas.hostname}"
          end

          lines.join("\n") + "\n"
        end
      end
    end
  end
end
