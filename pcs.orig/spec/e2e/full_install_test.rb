#!/usr/bin/env ruby
# frozen_string_literal: true

# Full Install E2E Test
#
# Validates: PXE boot → preseed install → post-install → SSH verification
# Runtime: ~3-5 min (KVM) / ~10-15 min (TCG)
# Requires: Linux, sudo, qemu-system-{aarch64,x86_64}, dnsmasq-base, internet

require "open3"
require "pathname"
require "timeout"
require "ostruct"
require_relative "support/e2e_root"
require_relative "support/test_bridge"
require "pcs/platform/arch"
require "pcs/platform/os"
require_relative "support/qemu_launcher"
require_relative "support/test_project"
require_relative "support/ssh_verifier"

module Pcs
  module E2E
    class FullInstallTest
      PXE_TIMEOUT = 60
      # KVM installs in ~3-5 min; TCG (cross-arch) can take 10-15 min on RPi
      KVM_INSTALL_TIMEOUT = 600
      TCG_INSTALL_TIMEOUT = 1200

      def initialize
        @arch = Pcs::Platform::Arch.resolve(ENV.fetch("PCS_E2E_ARCH", nil))
        Pcs::Platform::Arch.verify_dependencies!(@arch)

        @kvm = Pcs::Platform::Arch.kvm_available?(@arch)
        @install_timeout = @kvm ? KVM_INSTALL_TIMEOUT : TCG_INSTALL_TIMEOUT

        @bridge = TestBridge.new
        @qemu = QemuLauncher.new(arch: @arch)
        @project = TestProject.new(arch: @arch)
        @arch_config = Pcs::Platform::Arch.config_for(@arch)
        @ssh = nil
        @dnsmasq_pid = nil
        @netboot_pid = nil
        @uplink = nil
        @passed = 0
        @failed = 0
      end

      def run
        puts "=== Full Install E2E Test ==="
        puts "  Architecture: #{@arch} (#{@kvm ? "KVM" : "TCG"})"
        puts "  Install timeout: #{@install_timeout}s"
        puts "  This test takes #{@kvm ? "3-5" : "10-15"} minutes."
        setup
        wait_for_install
        verify
        report
      ensure
        teardown
      end

      private

      # ── Setup ──────────────────────────────────────────────

      def setup
        puts "\n--- Setup ---"

        puts "Scaffolding test project..."
        project_dir = @project.scaffold

        puts "Generating netboot configs via Netboot.reload..."
        Dir.chdir(project_dir) do
          Pcs.boot!(project_dir: project_dir)
          site = Pcs::Site.load(TestProject::SITE_NAME)
          Pcs::Service::Netboot.reload(site: site)
        end

        puts "Ensuring #{@arch} installer files..."
        ensure_installer_files

        puts "Patching preseed and boot menu for QEMU test..."
        patch_preseed_for_test
        patch_boot_menu_for_test

        puts "Creating test bridge..."
        @bridge.up

        puts "Enabling NAT for internet access..."
        enable_nat

        puts "Starting dnsmasq..."
        start_dnsmasq

        puts "Starting HTTP server for boot assets..."
        start_http_server

        puts "Launching QEMU VM (PXE boot, no-reboot)..."
        @qemu.start_pxe(ram: "2048", disk_size: "10G", no_reboot: true)
        puts "QEMU running (pid #{@qemu.pid})"
      end

      def ensure_installer_files
        dest_dir = Pcs::Service::Netboot.assets_dir / "debian-installer" / @arch
        dest_dir.mkpath

        kernel = dest_dir / "linux"
        initrd = dest_dir / "initrd.gz"

        return if kernel.exist? && initrd.exist?

        os = @project.os
        urls = Pcs::Platform::Os.installer_urls(os, @arch)
        system_cmd = Pcs::Adapters::SystemCmd.new

        unless kernel.exist?
          puts "  -> Downloading #{@arch} linux kernel..."
          system_cmd.run!("wget -q -O #{kernel} #{urls[:kernel_url]}")
        end

        unless initrd.exist?
          puts "  -> Downloading #{@arch} initrd.gz..."
          system_cmd.run!("wget -q -O #{initrd} #{urls[:initrd_url]}")
        end

        # Inject firmware if available
        firmware_url = Pcs::Platform::Os.firmware_url(os)
        if firmware_url
          firmware_path = dest_dir / "firmware.cpio.gz"
          initrd_orig = dest_dir / "initrd.gz.orig"

          if initrd_orig.exist?
            puts "  -> Firmware already injected"
          else
            unless firmware_path.exist?
              puts "  -> Downloading firmware.cpio.gz..."
              system_cmd.run!("wget -q -O #{firmware_path} #{firmware_url}")
            end

            puts "  -> Injecting firmware into initrd..."
            system_cmd.run!("cp #{initrd} #{initrd_orig}")
            system_cmd.run!("cat #{initrd_orig} #{firmware_path} > #{initrd}")
            puts "  -> Firmware injected"
          end
        end
      end

      def patch_preseed_for_test
        domain = "e2e.test"
        hostname = TestProject::VM_HOSTNAME
        preseed_path = Pcs::Service::Netboot.assets_dir / domain / "#{hostname}.preseed.cfg"

        unless preseed_path.exist?
          puts "  -> Warning: preseed not found at #{preseed_path}, skipping patch"
          return
        end

        content = preseed_path.read

        # 1. Replace LVM partitioning with simple atomic layout
        #    Match from the early_command (LVM wipe) through partman/confirm_nooverwrite
        content.sub!(
          /# Remove any existing LVM.*?d-i partman\/confirm_nooverwrite boolean true/m,
          <<~PRESEED.chomp
            # Partitioning — simple atomic layout for QEMU test
            d-i partman-auto/method string regular
            d-i partman-auto/choose_recipe select atomic
            d-i partman-partitioning/confirm_write_new_label boolean true
            d-i partman/choose_partition select finish
            d-i partman/confirm boolean true
            d-i partman/confirm_nooverwrite boolean true
          PRESEED
        )

        # 2. Fix kernel image for architecture
        kernel_image = @arch == "arm64" ? "linux-image-arm64" : "linux-image-amd64"
        content.sub!(/linux-image-amd64/, kernel_image)

        # 3. Replace vmbr0 bridge networking with simple eth0 static in late_command
        #    The late_command printf writes /etc/network/interfaces with a bridge setup.
        #    Replace with a simple static config.
        bridge_ip = @bridge.bridge_ip
        content.sub!(
          /printf 'auto lo\\n.*?\\n' > \/target\/etc\/network\/interfaces/,
          "printf 'auto lo\\niface lo inet loopback\\n\\nauto eth0\\niface eth0 inet static\\n" \
          "    address #{TestProject::VM_STATIC_IP}/24\\n" \
          "    gateway #{bridge_ip}\\n" \
          "    dns-nameservers 1.1.1.1 8.8.8.8\\n" \
          "    dns-search #{domain}\\n' > /target/etc/network/interfaces"
        )

        preseed_path.write(content)
        puts "  -> Patched #{preseed_path.basename}"
      end

      def patch_boot_menu_for_test
        boot_menu = Pcs::Service::Netboot.menus_dir / "pcs-boot.ipxe"
        return unless boot_menu.exist?

        content = boot_menu.read

        # Add net.ifnames=0 biosdevname=0 to kernel boot parameters
        # so the installed system uses eth0 instead of predictable names
        content.sub!(
          /netcfg\/dhcp_timeout=60/,
          "netcfg/dhcp_timeout=60 net.ifnames=0 biosdevname=0"
        )

        boot_menu.write(content)
        puts "  -> Patched pcs-boot.ipxe with net.ifnames=0"
      end

      def enable_nat
        cmd = Pcs::Adapters::SystemCmd.new
        result = cmd.run("ip route show default")
        @uplink = result.stdout[/dev\s+(\S+)/, 1]

        if @uplink
          cmd.run("iptables -t nat -A POSTROUTING -s 10.99.0.0/24 -o #{@uplink} -j MASQUERADE", sudo: true)
          cmd.run("iptables -A FORWARD -i #{TestBridge::BRIDGE_NAME} -o #{@uplink} -j ACCEPT", sudo: true)
          cmd.run("iptables -A FORWARD -i #{@uplink} -o #{TestBridge::BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT", sudo: true)
          puts "  -> NAT enabled via #{@uplink}"
        else
          puts "  -> Warning: no default route found, NAT not enabled"
        end
      end

      def disable_nat
        return unless @uplink

        cmd = Pcs::Adapters::SystemCmd.new
        cmd.run("iptables -t nat -D POSTROUTING -s 10.99.0.0/24 -o #{@uplink} -j MASQUERADE", sudo: true)
        cmd.run("iptables -D FORWARD -i #{TestBridge::BRIDGE_NAME} -o #{@uplink} -j ACCEPT", sudo: true)
        cmd.run("iptables -D FORWARD -i #{@uplink} -o #{TestBridge::BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT", sudo: true)
      end

      def start_dnsmasq
        ops_ip = @bridge.bridge_ip
        subnet_base = "10.99.0"
        netmask = "255.255.255.0"
        netboot_dir = DIRS[:netboot]
        boot_file = @arch_config[:ipxe_boot_file]

        config_path = E2E_ROOT / "dnsmasq.conf"
        dnsmasq_log = DIRS[:logs] / "dnsmasq.log"
        dnsmasq_log.write("")

        config_path.write(<<~CONF)
          port=0
          interface=#{TestBridge::BRIDGE_NAME}
          bind-dynamic
          dhcp-range=#{subnet_base}.100,#{subnet_base}.200,#{netmask},1h
          dhcp-option=option:router,#{ops_ip}
          dhcp-option=option:dns-server,1.1.1.1,8.8.8.8
          dhcp-boot=#{boot_file},,#{ops_ip}
          log-dhcp
          log-facility=#{dnsmasq_log}
          enable-tftp
          tftp-root=#{netboot_dir / "menus"}
        CONF

        @dnsmasq_pid = Process.spawn(
          "sudo", "dnsmasq",
          "--no-daemon",
          "--conf-file=#{config_path}",
          out: "/dev/null",
          err: dnsmasq_log.to_s
        )

        sleep 1
        unless process_running?(@dnsmasq_pid)
          raise "dnsmasq failed to start. Check #{dnsmasq_log}"
        end
      end

      def start_http_server
        assets_dir = DIRS[:netboot] / "assets"
        http_log = DIRS[:logs] / "http.log"

        @netboot_pid = Process.spawn(
          "ruby", "-run", "-e", "httpd",
          "--", "--port=8080", "--bind-address=#{@bridge.bridge_ip}",
          "-d", assets_dir.to_s,
          out: http_log.to_s,
          err: http_log.to_s
        )

        sleep 1
        unless process_running?(@netboot_pid)
          raise "HTTP server failed to start. Check #{http_log}"
        end
      end

      # ── Wait for Install ───────────────────────────────────

      def wait_for_install
        puts "\n--- Waiting for Install ---"
        puts "  PXE boot + Debian preseed install (timeout: #{@install_timeout}s)..."

        dnsmasq_log = DIRS[:logs] / "dnsmasq.log"

        puts "  Waiting for PXE handshake..."
        Timeout.timeout(PXE_TIMEOUT) do
          loop do
            log = dnsmasq_log.read rescue ""
            break if log.include?("DHCPACK")
            sleep 2
          end
        end
        puts "  PXE handshake complete."

        puts "  Waiting for install to complete (VM will exit on reboot)..."
        @qemu.wait_for_exit(timeout: @install_timeout)
        puts "  Install complete — VM exited."

        puts "  Booting from installed disk..."
        @qemu.start_disk(ram: "2048")
        puts "  QEMU running (pid #{@qemu.pid})"

        puts "  Waiting for SSH..."
        username = ENV.fetch("USER", "admin")
        @ssh = SshVerifier.new(
          host: TestProject::VM_STATIC_IP,
          user: username,
          key_path: @project.ssh_private_key_path.to_s
        )
        @ssh.wait_for_ssh(timeout: 120)
        puts "  VM is up and SSH is reachable!"

      rescue Timeout::Error => e
        puts "  TIMEOUT: #{e.message}"
        puts "  The install did not complete within the timeout."
        puts "  Check QEMU log: #{DIRS[:logs] / "qemu.log"}"
      end

      # ── Verification ───────────────────────────────────────

      def verify
        puts "\n--- Verification ---"

        return skip_verification("SSH not available") unless @ssh

        username = ENV.fetch("USER", "admin")

        assert("Hostname is set correctly") do
          actual = @ssh.run("hostname")
          actual == TestProject::VM_HOSTNAME
        end

        assert("Static IP is configured") do
          output = @ssh.run("ip -4 addr show")
          output.include?(TestProject::VM_STATIC_IP)
        end

        assert("SSH authorized_keys deployed") do
          @ssh.assert_file_exists("/home/#{username}/.ssh/authorized_keys")
        end

        assert("Passwordless sudo configured") do
          @ssh.assert_file_exists("/etc/sudoers.d/#{username}")
        end

        assert("Post-install script downloaded") do
          @ssh.assert_file_exists("/home/#{username}/post-install.sh")
        end

        assert("DNS resolution works") do
          result = @ssh.run("host -W 5 deb.debian.org") rescue nil
          result && result.include?("has address")
        end

        assert("SSH server is running") do
          @ssh.assert_service_active("ssh")
        end

        assert("Timezone is UTC") do
          tz = @ssh.run("cat /etc/timezone")
          tz.strip == "UTC"
        end

        assert("Correct architecture") do
          uname = @ssh.run("uname -m")
          expected = @arch == "arm64" ? "aarch64" : "x86_64"
          uname.strip == expected
        end
      end

      def skip_verification(reason)
        puts "  Skipping verification: #{reason}"
        @failed += 1
      end

      # ── Reporting ──────────────────────────────────────────

      def report
        puts "\n--- Results ---"
        total = @passed + @failed
        puts "#{@passed}/#{total} passed (#{@arch}, #{@kvm ? "KVM" : "TCG"})"

        if @failed > 0
          puts "\nDebug logs (all under #{E2E_ROOT}):"
          puts "  dnsmasq: #{DIRS[:logs] / "dnsmasq.log"}"
          puts "  HTTP:    #{DIRS[:logs] / "http.log"}"
          puts "  QEMU:    #{DIRS[:logs] / "qemu.log"}"
          puts "\nTo inspect the VM manually:"
          puts "  ssh -i #{@project.ssh_private_key_path} -o StrictHostKeyChecking=no #{ENV.fetch("USER", "admin")}@#{TestProject::VM_STATIC_IP}"
          exit 1
        end
      end

      # ── Teardown ───────────────────────────────────────────

      def teardown
        puts "\n--- Teardown ---"

        @qemu.stop if @qemu&.running?

        if @dnsmasq_pid
          system("sudo kill #{@dnsmasq_pid} 2>/dev/null")
          Process.wait(@dnsmasq_pid) rescue nil
        end

        if @netboot_pid
          Process.kill("TERM", @netboot_pid) rescue nil
          Process.wait(@netboot_pid) rescue nil
        end

        disable_nat
        @bridge&.down
        @project&.cleanup

        puts "Teardown complete."
      end

      # ── Helpers ────────────────────────────────────────────

      def assert(description)
        result = yield
        if result
          @passed += 1
          puts "  ✓ #{description}"
        else
          @failed += 1
          puts "  ✗ #{description}"
        end
      rescue StandardError => e
        @failed += 1
        puts "  ✗ #{description} (#{e.message})"
      end

      def process_running?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
    end
  end
end

Pcs::E2E::FullInstallTest.new.run if __FILE__ == $PROGRAM_NAME
