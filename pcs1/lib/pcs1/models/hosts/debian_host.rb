# frozen_string_literal: true

module Pcs1
  class DebianHost < Host
    sti_type "debian"

    # Debian hosts that are PXE-booted get SSH keys via preseed,
    # so keying is skipped. Override the state machine to allow
    # discovered → configured directly (skip keyed).
    state_machine :status do
      event :configure do
        transition [:discovered, :keyed] => :configured, if: :configuration_complete?
      end
    end

    # Keying is a no-op for PXE targets — keys come from preseed.
    # If the host is already running Debian (not PXE), the base key! works.
    def key!
      if status == "discovered"
        Pcs1.logger.info("Debian PXE target — SSH keys will be installed via preseed.")
        Pcs1.logger.info("Skipping key push. Configure this host to proceed.")
        return
      end

      super
    end

    def restart_networking!
      Pcs1.logger.info("Restarting networking on #{hostname || id}...")
      ssh_exec!("systemctl restart networking")
    rescue StandardError
      Pcs1.logger.warn("Networking restart failed, rebooting...")
      begin
        ssh_exec!("reboot")
      rescue StandardError
        # Expected — SSH drops on reboot
      end
    end

    def self.detect?(ssh)
      result = ssh.exec!("cat /etc/os-release 2>/dev/null")
      !result.nil? && result.include?("ID=debian")
    rescue StandardError
      false
    end

    # --- Install file generation (called by Netboot service) ---

    def generate_install_files(output_dir)
      return unless hostname && interfaces.first&.configured_ip

      site = self.site
      network = site.networks.detect(&:primary)
      return unless network

      iface = interfaces.first
      base_url = "http://#{cp_ops_ip}:#{Pcs1.config.netboot.http_port}/#{site.domain}"

      vars = preseed_vars(site, network, iface, base_url)

      write_template("debian/preseed.cfg.erb", output_dir / "#{hostname}.preseed.cfg", vars)
      write_template("debian/post-install.sh.erb", output_dir / "#{hostname}.install.sh", {
        hostname: hostname,
        domain: site.domain || "local"
      })
    end

    def kernel_params(base_url:)
      domain = site&.domain || "local"
      "auto=true priority=critical locale=en_US.UTF-8 keymap=us language=en country=US " \
      "netcfg/choose_interface=auto hostname=#{hostname} domain=#{domain} " \
      "preseed/url=#{base_url}/#{domain}/#{hostname}.preseed.cfg " \
      "preseed/interactive=false vga=788 netcfg/dhcp_timeout=60"
    end

    def boot_menu_entry
      {
        key: "install",
        label: "Debian preseed (automated) - ${host}",
        kernel_path: "debian-installer/#{arch || "amd64"}/linux",
        initrd_path: "debian-installer/#{arch || "amd64"}/initrd.gz"
      }
    end

    private

    def preseed_vars(site, network, iface, base_url)
      gateway = network.gateway
      dns_resolvers = network.dns_resolvers || [gateway]
      prefix_length = network.subnet.split("/").last

      defaults = Pcs1.config.host_defaults["debian"] || {}
      username = defaults[:user] || "admin"
      password = defaults[:password] || "changeme123!"

      authorized_keys_url = nil
      authorized_keys_url = "#{base_url}/authorized_keys" if site.ssh_public_key_content

      {
        hostname: hostname,
        domain: site.domain || "local",
        username: username,
        password: password,
        timezone: site.timezone || "UTC",
        device: preseed_device,
        interface: iface.name || "enp1s0",
        packages: "openssh-server curl sudo",
        base_url: base_url,
        authorized_keys_url: authorized_keys_url,
        ip_address: iface.configured_ip,
        prefix_length: prefix_length,
        gateway: gateway,
        nameservers: dns_resolvers.join(" ")
      }
    end

    def preseed_device
      "/dev/sda"
    end

    def cp_ops_ip
      cp = site.hosts.detect { |h| h.role == "cp" }
      return nil unless cp
      cp.interfaces.first&.reachable_ip
    end

    def write_template(relative_path, output_path, vars)
      template_path = Pcs1.resolve_template(relative_path)
      template = ERB.new(template_path.read, trim_mode: "-")
      content = template.result_with_hash(**vars)
      Platform.sudo_write(output_path, content)
    end
  end
end
