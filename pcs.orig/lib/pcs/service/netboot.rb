# frozen_string_literal: true

require "pathname"
require "erb"

module Pcs
  module Service
    class Netboot
      TEMPLATE_DIR = Pathname.new(__dir__).join("..", "templates", "netboot")
      MENU_TEMPLATE          = TEMPLATE_DIR / "pcs-menu.ipxe.erb"
      MAC_TEMPLATE           = TEMPLATE_DIR / "mac-boot.ipxe.erb"
      PRESEED_TEMPLATE       = TEMPLATE_DIR / "preseed.cfg.erb"
      POST_INSTALL_TEMPLATE  = TEMPLATE_DIR / "post-install.sh.erb"

      def self.netboot_dir = Pcs.config.service.netboot.netboot_dir
      def self.menus_dir   = netboot_dir / "menus"
      def self.assets_dir  = netboot_dir / "assets"
      def self.custom_dir  = netboot_dir / "custom"

      def self.start(site:, system_cmd: Adapters::SystemCmd.new)
        unless system_cmd.command_exists?("podman")
          raise "podman not found. Run 'pcs init' first to install dependencies."
        end

        # Skip if container is already running
        check = system_cmd.run("podman inspect netbootxyz --format '{{.State.Status}}'", sudo: true)
        if check.success? && check.stdout.strip == "running"
          puts "  -> Already running"
          return
        end

        ensure_dirs(system_cmd: system_cmd)
        generate_all(site: site, system_cmd: system_cmd)
        download_boot_files(system_cmd: system_cmd)

        image = Pcs.config.service.netboot.image

        if system_cmd.run("podman image exists #{image}", sudo: true).success?
          puts "  -> Image #{image} already present"
        else
          puts "  -> Pulling #{image}..."
          system_cmd.run!("podman pull #{image}", sudo: true)
        end

        system_cmd.run("podman rm -f netbootxyz", sudo: true)

        puts "  -> Starting container..."
        system_cmd.run!(
          "podman run -d " \
          "--name netbootxyz " \
          "--restart unless-stopped " \
          "-p 3000:3000 " \
          "-p 69:69/udp " \
          "-p 8080:80 " \
          "-v #{netboot_dir}:/config " \
          "-v #{assets_dir}:/assets " \
          "#{image}",
          sudo: true
        )
        puts "  -> Running on :3000 (web UI), :69/udp (TFTP), :8080 (HTTP assets)"
      end

      def self.reload(site:, system_cmd: Adapters::SystemCmd.new)
        ensure_dirs(system_cmd: system_cmd)
        generate_all(site: site, system_cmd: system_cmd)
        download_boot_files(system_cmd: system_cmd)
      end

      def self.status(system_cmd: Adapters::SystemCmd.new)
        result = system_cmd.run("podman inspect netbootxyz --format '{{.State.Status}}'")
        return result.stdout.strip if result.success?

        # Rootful container — try with sudo (non-interactive only)
        result = system_cmd.run("sudo -n podman inspect netbootxyz --format '{{.State.Status}}'")
        result.success? ? result.stdout.strip : "stopped"
      end

      def self.log_command = "sudo podman logs -f netbootxyz"

      def self.status_report(system_cmd: Adapters::SystemCmd.new, pastel: Pastel.new, lines: 20)
        puts pastel.cyan.bold("netboot status")
        puts

        # Container status
        puts pastel.bold("Container:")
        result = system_cmd.run("podman inspect netbootxyz --format '{{.State.Status}} (pid {{.State.Pid}}, started {{.State.StartedAt}})'", sudo: true)
        if result.success?
          puts "  status: #{result.stdout.strip}"
        else
          puts "  status: not found"
        end

        image = system_cmd.run("podman inspect netbootxyz --format '{{.ImageName}}'", sudo: true)
        puts "  image: #{image.success? ? image.stdout.strip : "-"}"
        puts

        # Ports
        puts pastel.bold("Ports:")
        tftp = system_cmd.run("ss -ulnp sport = :69")
        if tftp.stdout.include?(":69")
          puts "  udp/69 (TFTP): #{pastel.green("listening")}"
        else
          puts "  udp/69 (TFTP): #{pastel.red("not listening")}"
        end

        web = system_cmd.run("ss -tlnp sport = :3000")
        if web.stdout.include?(":3000")
          puts "  tcp/3000 (web UI): #{pastel.green("listening")}"
        else
          puts "  tcp/3000 (web UI): #{pastel.red("not listening")}"
        end

        http = system_cmd.run("ss -tlnp sport = :8080")
        if http.stdout.include?(":8080")
          puts "  tcp/8080 (HTTP assets): #{pastel.green("listening")}"
        else
          puts "  tcp/8080 (HTTP assets): #{pastel.red("not listening")}"
        end
        puts

        # Web UI
        puts pastel.bold("Web UI:")
        curl = system_cmd.run("curl -s -o /dev/null -w '%{http_code}' http://localhost:3000")
        code = curl.stdout.strip
        if code == "200"
          puts "  http://localhost:3000: #{pastel.green("OK (#{code})")}"
        else
          puts "  http://localhost:3000: #{pastel.red("FAIL (#{code})")}"
        end
        puts

        # Boot files
        puts pastel.bold("Netboot files (#{menus_dir}/):")
        %w[netboot.xyz.efi netboot.xyz.kpxe netboot.xyz-arm64.efi].each do |f|
          path = menus_dir / f
          if path.exist?
            puts "  #{f}: #{pastel.green("present")}"
          else
            puts "  #{f}: #{pastel.red("missing")}"
          end
        end

        puts pastel.bold("PCS menus (#{menus_dir}/):")
        pxe_boot = menus_dir / "pcs-boot.ipxe"
        if pxe_boot.exist?
          puts "  pcs-boot.ipxe: #{pastel.green("present")}"
        else
          puts "  pcs-boot.ipxe: #{pastel.red("missing")}"
        end

        mac_files = menus_dir.exist? ? menus_dir.glob("MAC-*.ipxe") : []
        if mac_files.any?
          mac_files.each { |f| puts "  #{f.basename}: #{pastel.green("present")}" }
        else
          puts "  (no MAC files)"
        end

        puts pastel.bold("Debian installer (#{assets_dir}/debian-installer/amd64/):")
        %w[linux initrd.gz].each do |f|
          path = assets_dir / "debian-installer" / "amd64" / f
          if path.exist?
            puts "  #{f}: #{pastel.green("present")}"
          else
            puts "  #{f}: #{pastel.red("missing")}"
          end
        end

        # Per-domain assets
        puts pastel.bold("Install assets (#{assets_dir}/):")
        (assets_dir.exist? ? assets_dir.children : []).select(&:directory?).sort.each do |child|
          next if %w[debian-installer].include?(child.basename.to_s)

          puts "  #{child.basename}/"
          child.children.sort.each do |f|
            puts "    #{f.basename}: #{pastel.green("present")}"
          end
        end
        puts

        # Container logs
        puts pastel.bold("Recent logs (last #{lines} lines):")
        logs = system_cmd.run("podman logs --tail #{lines} netbootxyz", sudo: true)
        if logs.success?
          logs.stdout.each_line { |l| puts "  #{l}" }
          logs.stderr.each_line { |l| puts "  #{l}" } if logs.stdout.strip.empty?
        else
          puts "  (no logs available)"
        end
      end

      def self.stop(system_cmd: Adapters::SystemCmd.new)
        system_cmd.run("podman stop netbootxyz", sudo: true)
        system_cmd.run("podman rm netbootxyz", sudo: true)
        puts "  -> netbootxyz stopped and removed"
      end

      # --- Private class methods ---

      def self.ensure_dirs(system_cmd:)
        [netboot_dir, menus_dir, assets_dir, custom_dir].each do |dir|
          next if dir.exist?

          system_cmd.run!("mkdir -p #{dir}", sudo: true)
        end
      end
      private_class_method :ensure_dirs

      def self.download_boot_files(system_cmd:, arch: Platform::Arch.native, os: nil)
        os ||= Pcs.config.service.netboot.default_os
        urls = Platform::Os.installer_urls(os, arch)
        kernel_url = urls[:kernel_url]
        initrd_url = urls[:initrd_url]

        dest_dir = assets_dir / "debian-installer" / arch
        system_cmd.run!("mkdir -p #{dest_dir}", sudo: true)

        kernel_path = dest_dir / "linux"
        initrd_path = dest_dir / "initrd.gz"

        download_file(kernel_url, kernel_path, system_cmd: system_cmd)
        download_file(initrd_url, initrd_path, system_cmd: system_cmd)

        inject_firmware(os: os, initrd_path: initrd_path, system_cmd: system_cmd)

        puts "  -> Debian installer files ready in #{dest_dir}"
      end
      private_class_method :download_boot_files

      def self.inject_firmware(os:, initrd_path:, system_cmd:)
        firmware_url = Platform::Os.firmware_url(os)
        return unless firmware_url

        firmware_path = initrd_path.dirname / "firmware.cpio.gz"
        initrd_orig = initrd_path.dirname / "initrd.gz.orig"

        # Already injected — skip
        if initrd_orig.exist?
          puts "  -> Firmware already injected"
          return
        end

        download_file(firmware_url, firmware_path, system_cmd: system_cmd)

        puts "  -> Injecting firmware into initrd..."
        system_cmd.run!("cp #{initrd_path} #{initrd_orig}", sudo: true)
        system_cmd.run!("cat #{initrd_orig} #{firmware_path} > #{initrd_path}", sudo: true)
        puts "  -> Firmware injected"
      end
      private_class_method :inject_firmware

      def self.download_file(url, dest_path, system_cmd:)
        if dest_path.exist?
          puts "  -> #{dest_path.basename} already present"
        else
          puts "  -> Downloading #{dest_path.basename}..."
          system_cmd.run!("wget -q -O #{dest_path} #{url}", sudo: true)
        end
      end
      private_class_method :download_file

      def self.generate_all(site:, system_cmd:)
        pve_hosts = Pcs::Host.hosts_of_type("proxmox")

        cp_host = Pcs::Host.find_by(role: "cp")
        ops_ip = cp_host && (cp_host.ip_on(:compute) || cp_host.discovered_ip)

        domain = site.domain || "local"

        unless cp_host && ops_ip
          puts "  -> Warning: no cp device with an IP found in inventory"
          puts "     Run 'pcs network scan' to populate inventory, then reload"
          generate_custom_hook(system_cmd: system_cmd)
          return
        end

        generate_pxe_files(pve_hosts: pve_hosts, ops_ip: ops_ip, domain: domain, system_cmd: system_cmd)
        generate_install_files(site: site, pve_hosts: pve_hosts, ops_ip: ops_ip, domain: domain, system_cmd: system_cmd)
        generate_custom_hook(system_cmd: system_cmd)
      end
      private_class_method :generate_all

      def self.generate_pxe_files(pve_hosts:, ops_ip:, domain:, system_cmd:)
        ipxe_timeout_sec = Pcs.config.service.netboot.ipxe_timeout
        ipxe_timeout = ipxe_timeout_sec.to_i * 1000

        menu_template = ERB.new(MENU_TEMPLATE.read, trim_mode: "-")
        menu_content = menu_template.result_with_hash(
          ops_ip: ops_ip,
          domain: domain,
          ipxe_timeout: ipxe_timeout
        )

        # Write as pcs-boot.ipxe (referenced by custom.ipxe fallback chain)
        # NOTE: we do NOT overwrite menu.ipxe — that belongs to the netboot.xyz distribution
        boot_path = menus_dir / "pcs-boot.ipxe"
        system_cmd.file_write(boot_path, menu_content, sudo: true)
        puts "  -> Generated #{boot_path}"

        mac_template = ERB.new(MAC_TEMPLATE.read, trim_mode: "-")
        pve_hosts.each do |dev|
          next unless dev.mac

          mac_stripped = dev.mac.downcase.delete(":")
          content = mac_template.result_with_hash(
            mac_stripped: mac_stripped,
            hostname: dev.hostname,
            ip: dev.ip_on(:compute) || dev.discovered_ip,
            arch: dev.arch || "amd64",
            domain: domain
          )

          mac_path = menus_dir / "MAC-#{mac_stripped}.ipxe"
          system_cmd.file_write(mac_path, content, sudo: true)
          puts "  -> Generated #{mac_path}"
        end

        puts "  -> #{pve_hosts.size} PVE device(s)"
      end
      private_class_method :generate_pxe_files

      def self.generate_install_files(site:, pve_hosts:, ops_ip:, domain:, system_cmd:)
        return if pve_hosts.empty?

        domain_dir = assets_dir / domain
        system_cmd.run!("mkdir -p #{domain_dir}", sudo: true) unless domain_dir.exist?

        cfg = Pcs.config
        username = ENV.fetch("USER", "admin")
        password = cfg.default_root_password
        timezone = site.timezone || "UTC"
        packages = cfg.default_packages
        base_url = "http://#{ops_ip}:8080/#{domain}"

        compute = site.network(:compute)
        gateway = compute&.gateway || ""
        dns_resolvers = compute&.dns_resolvers || cfg.networking.dns_fallback_resolvers
        subnet = compute&.subnet || ""
        prefix_length = subnet.split("/").last
        nameservers = dns_resolvers.join(" ")

        # Copy SSH authorized_keys
        authorized_keys_url = nil
        ssh_key = site.ssh_key
        if ssh_key
          expanded = Pathname.new(ssh_key).expand_path
          if expanded.exist?
            dest = domain_dir / "authorized_keys"
            system_cmd.file_write(dest, expanded.read, sudo: true)
            authorized_keys_url = "#{base_url}/authorized_keys"
            puts "  -> Copied SSH keys to #{dest}"
          end
        end

        all_peers = (Pcs::Host.hosts_of_type("proxmox") + Pcs::Host.hosts_of_type("truenas"))
                      .select { |d| d.hostname && d.ip_on(:compute) }

        preseed_template = ERB.new(PRESEED_TEMPLATE.read, trim_mode: "-")
        post_install_template = ERB.new(POST_INSTALL_TEMPLATE.read, trim_mode: "-")

        pve_hosts.each do |dev|
          next unless dev.hostname

          ip_address = dev.ip_on(:compute) || dev.discovered_ip
          next unless ip_address

          device = dev.preseed_device || "/dev/nvme0n1"
          interface = dev.interface_name || "enp1s0"

          peers = all_peers.reject { |d| d.hostname == dev.hostname }

          preseed_content = preseed_template.result_with_hash(
            hostname: dev.hostname,
            username: username,
            password: password,
            timezone: timezone,
            domain: domain,
            device: device,
            interface: interface,
            packages: packages,
            base_url: base_url,
            authorized_keys_url: authorized_keys_url,
            ip_address: ip_address,
            prefix_length: prefix_length,
            gateway: gateway,
            nameservers: nameservers,
            peers: peers
          )
          system_cmd.file_write(domain_dir / "#{dev.hostname}.preseed.cfg", preseed_content, sudo: true)
          puts "  -> Generated #{domain_dir / "#{dev.hostname}.preseed.cfg"}"

          post_install_content = post_install_template.result_with_hash(
            hostname: dev.hostname,
            domain: domain
          )
          system_cmd.file_write(domain_dir / "#{dev.hostname}.install.sh", post_install_content, sudo: true)
          puts "  -> Generated #{domain_dir / "#{dev.hostname}.install.sh"}"
        end
      end
      private_class_method :generate_install_files

      def self.generate_custom_hook(system_cmd:)
        custom_ipxe = <<~IPXE
          #!ipxe
          # PCS managed — netboot.xyz custom hook
          # Try per-MAC boot script, fall back to PCS menu, then netboot.xyz default
          chain --replace MAC-${mac:hexraw}.ipxe || chain --replace pcs-boot.ipxe || goto netbootxyz
          :netbootxyz
          # Reduce netboot.xyz fallback menu timeout from 300s to 3s
          set boot_timeout 3000
          exit
        IPXE
        system_cmd.file_write(custom_dir / "custom.ipxe", custom_ipxe, sudo: true)
        puts "  -> Generated #{custom_dir / "custom.ipxe"}"
      end
      private_class_method :generate_custom_hook
    end
  end
end
