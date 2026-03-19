# frozen_string_literal: true

module Pcs1
  class Netboot < Service
    def self.netboot_dir
      Pathname(Pcs1.config.netboot.netboot_dir)
    end

    def self.menus_dir  = netboot_dir / "menus"
    def self.assets_dir = netboot_dir / "assets"
    def self.custom_dir = netboot_dir / "custom"

    # --- Lifecycle ---

    def self.reconcile!(exclude_ips: [])
      ensure_dirs
      generate_all(exclude_ips: exclude_ips)
    end

    def self.start!
      config = Pcs1.config.netboot

      raise "podman not found. Install podman first." unless command_exists?("podman")

      if status == "running"
        logger.info("netboot: already running")
        return
      end

      ensure_dirs
      generate_all(exclude_ips: Host.local_ips)

      image = config.image
      unless system("sudo podman image exists #{image} 2>/dev/null")
        logger.info("netboot: pulling #{image}...")
        system_cmd("sudo podman pull #{image}")
      end

      system_cmd("sudo podman rm -f netbootxyz", raise_on_error: false)

      logger.info("netboot: starting container...")
      system_cmd(
        "sudo podman run -d " \
        "--name netbootxyz " \
        "--restart unless-stopped " \
        "-p #{config.web_port}:3000 " \
        "-p #{config.tftp_port}:69/udp " \
        "-p #{config.http_port}:80 " \
        "-v #{netboot_dir}:/config " \
        "-v #{assets_dir}:/assets " \
        "#{image}"
      )
      logger.info("netboot: running on :#{config.web_port} (web), :#{config.tftp_port}/udp (TFTP), :#{config.http_port} (HTTP)")
    end

    def self.stop!
      system_cmd("sudo podman stop netbootxyz", raise_on_error: false)
      system_cmd("sudo podman rm netbootxyz", raise_on_error: false)
      logger.info("netboot: stopped and removed")
    end

    def self.status
      capture("sudo podman inspect netbootxyz --format '{{.State.Status}}'").then do |r|
        r.empty? ? "stopped" : r
      end
    end

    # --- File generation ---

    def self.generate_all(exclude_ips: [])
      site = Pcs1.site
      config = Pcs1.config.netboot

      cp_host = site.hosts.detect { |h| h.role == "cp" }
      return logger.warn("netboot: no CP host found, skipping generation") unless cp_host

      ops_ip = cp_host.interfaces.first&.reachable_ip
      return logger.warn("netboot: CP has no IP, skipping generation") unless ops_ip

      domain = site.domain || "local"

      pxe_hosts = site.hosts.select do |h|
        h.pxe_target? &&
          h.status == "configured" &&
          h.hostname &&
          h.interfaces.any? { |i| i.mac && i.configured_ip }
      end
      pxe_hosts.reject! { |h| h.interfaces.any? { |i| exclude_ips.include?(i.configured_ip) } }

      copy_ssh_key(site, domain)

      pxe_hosts.each do |host|
        host_assets_dir = assets_dir / domain
        host.generate_install_files(host_assets_dir)
        generate_mac_script(host, domain)
      end

      generate_menu(pxe_hosts, ops_ip, domain, config)
      generate_custom_hook

      logger.info("netboot: generated files for #{pxe_hosts.size} PXE host(s)")
    end

    # --- Private generation methods ---

    def self.generate_mac_script(host, domain)
      iface = host.interfaces.first
      return unless iface&.mac

      mac_stripped = iface.mac.downcase.delete(":")

      content = render_template("netboot/mac-boot.ipxe.erb",
                                mac_stripped: mac_stripped,
                                hostname: host.hostname,
                                ip: iface.configured_ip,
                                arch: host.arch || "amd64",
                                domain: domain)

      sudo_write(menus_dir / "MAC-#{mac_stripped}.ipxe", content)
    end

    def self.generate_menu(pxe_hosts, ops_ip, domain, config)
      install_entries = pxe_hosts.filter_map do |host|
        entry = host.boot_menu_entry
        next unless entry

        base_url = "http://#{ops_ip}:#{config.http_port}"
        params = host.kernel_params(base_url: base_url)
        entry.merge(kernel_params: params || "")
      end.uniq { |e| e[:key] }

      content = render_template("netboot/pcs-menu.ipxe.erb",
                                ops_ip: ops_ip,
                                http_port: config.http_port,
                                domain: domain,
                                ipxe_timeout: 10_000,
                                install_entries: install_entries)

      sudo_write(menus_dir / "pcs-boot.ipxe", content)
    end

    def self.generate_custom_hook
      content = render_template("netboot/custom.ipxe.erb", {})
      sudo_write(custom_dir / "custom.ipxe", content)
    end

    def self.copy_ssh_key(site, domain)
      pub_key = site.ssh_public_key_content
      return unless pub_key

      sudo_write(assets_dir / domain / "authorized_keys", pub_key)
    end

    def self.ensure_dirs
      [netboot_dir, menus_dir, assets_dir, custom_dir].each do |dir|
        next if dir.exist?

        system_cmd("sudo mkdir -p #{dir}")
      end
    end

    private_class_method :generate_mac_script, :generate_menu, :generate_custom_hook,
                         :copy_ssh_key, :ensure_dirs
  end
end
