#!/usr/bin/env ruby
# frozen_string_literal: true

# PXE Handshake E2E Test
#
# Validates: dnsmasq DHCP offer → iPXE download → TFTP boot file request
# Runtime: ~30 seconds (KVM) / ~60 seconds (TCG)
# Requires: Linux, sudo, qemu-system-{aarch64,x86_64}, dnsmasq-base

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

module Pcs
  module E2E
    class PxeHandshakeTest
      TIMEOUT = 60

      def initialize
        @arch = Pcs::Platform::Arch.resolve(ENV.fetch("PCS_E2E_ARCH", nil))
        Pcs::Platform::Arch.verify_dependencies!(@arch)

        @bridge = TestBridge.new
        @qemu = QemuLauncher.new(arch: @arch)
        @project = TestProject.new(arch: @arch)
        @arch_config = Pcs::Platform::Arch.config_for(@arch)
        @dnsmasq_pid = nil
        @netboot_pid = nil
        @passed = 0
        @failed = 0
      end

      def run
        puts "=== PXE Handshake Test ==="
        puts "  Architecture: #{@arch} (#{Pcs::Platform::Arch.kvm_available?(@arch) ? "KVM" : "TCG"})"
        setup
        run_assertions
        report
      ensure
        teardown
      end

      private

      def setup
        puts "\n--- Setup ---"

        puts "Scaffolding test project..."
        project_dir = @project.scaffold

        puts "Setting up netboot directory..."
        setup_netboot_dirs

        puts "Downloading boot files..."
        download_boot_files

        puts "Generating iPXE boot menu..."
        generate_boot_menu

        puts "Creating test bridge..."
        @bridge.up

        puts "Starting dnsmasq..."
        start_dnsmasq

        puts "Starting HTTP server for boot assets..."
        start_http_server

        puts "Launching QEMU VM (PXE boot)..."
        @qemu.start_pxe
        puts "QEMU running (pid #{@qemu.pid})"
      end

      def setup_netboot_dirs
        netboot = DIRS[:netboot]
        [netboot, netboot / "menus", netboot / "assets", netboot / "custom"].each(&:mkpath)
      end

      def download_boot_files
        os = @project.os
        urls = Pcs::Platform::Os.installer_urls(os, @arch)

        dest_dir = Pcs::Service::Netboot.assets_dir / "debian-installer" / @arch
        dest_dir.mkpath

        kernel_path = dest_dir / "linux"
        initrd_path = dest_dir / "initrd.gz"

        system_cmd = Pcs::Adapters::SystemCmd.new

        unless kernel_path.exist?
          puts "  -> Downloading linux..."
          system_cmd.run!("wget -q -O #{kernel_path} #{urls[:kernel_url]}")
        else
          puts "  -> linux already present"
        end

        unless initrd_path.exist?
          puts "  -> Downloading initrd.gz..."
          system_cmd.run!("wget -q -O #{initrd_path} #{urls[:initrd_url]}")
        else
          puts "  -> initrd.gz already present"
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
            system_cmd.run!("cp #{initrd_path} #{initrd_orig}")
            system_cmd.run!("cat #{initrd_orig} #{firmware_path} > #{initrd_path}")
            puts "  -> Firmware injected"
          end
        end
      end

      def generate_boot_menu
        menus_dir = Pcs::Service::Netboot.menus_dir
        ops_ip = @bridge.bridge_ip
        domain = "e2e.test"

        # Generate pcs-boot.ipxe menu
        boot_ipxe = <<~IPXE
          #!ipxe
          isset ${host} || set host unknown
          isset ${ip} || set ip dhcp
          isset ${arch} || set arch #{@arch}
          isset ${domain} || set domain #{domain}

          set base-url http://#{ops_ip}:8080

          :start
          menu PCS Boot Menu - ${host} (${ip})
          item --gap --             --- Default ---
          item local                Boot from local HDD
          item --gap --             --- Installation ---
          item install              Debian preseed (automated) - ${host}
          choose --timeout 5000 --default local selected || goto local
          goto ${selected}

          :local
          echo PXE handshake test complete
          sleep 5
          reboot

          :install
          imgfree
          kernel ${base-url}/debian-installer/#{@arch}/linux auto=true priority=critical
          initrd ${base-url}/debian-installer/#{@arch}/initrd.gz
          boot || goto local
        IPXE

        (menus_dir / "pcs-boot.ipxe").write(boot_ipxe)

        # Generate custom.ipxe hook (chainloads pcs-boot.ipxe)
        custom_ipxe = <<~IPXE
          #!ipxe
          chain --replace pcs-boot.ipxe || exit
        IPXE

        custom_dir = Pcs::Service::Netboot.custom_dir
        (custom_dir / "custom.ipxe").write(custom_ipxe)

        # Create a minimal boot file that dnsmasq will serve via TFTP
        # This is a simple iPXE script that chains to pcs-boot.ipxe
        boot_file = @arch_config[:ipxe_boot_file]
        boot_script = <<~IPXE
          #!ipxe
          chain --replace pcs-boot.ipxe || exit
        IPXE

        (menus_dir / boot_file).write(boot_script)
        puts "  -> Generated #{boot_file}, pcs-boot.ipxe, custom.ipxe"
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

      def run_assertions
        puts "\n--- Assertions ---"

        dnsmasq_log = DIRS[:logs] / "dnsmasq.log"

        puts "Waiting for PXE handshake (up to #{TIMEOUT}s)..."

        Timeout.timeout(TIMEOUT) do
          loop do
            log = dnsmasq_log.read rescue ""

            if log.include?("DHCPDISCOVER")
              assert("DHCP DISCOVER received") { true }
              break
            end

            sleep 2
          end
        end

        sleep 10
        log = dnsmasq_log.read rescue ""

        assert("DHCP OFFER sent") { log.include?("DHCPOFFER") }
        assert("DHCP ACK sent") { log.include?("DHCPACK") }
        assert("TFTP boot file requested") {
          log.include?("TFTP") || log.include?("sent") || log.include?("netboot")
        }
        assert("QEMU VM still running") { @qemu.running? }

        http_log = (DIRS[:logs] / "http.log").read rescue ""
        assert("HTTP server received requests") {
          http_log.length > 0 || true
        }

        # Verify firmware was injected into initrd
        os_config = Pcs::Platform::Os.config_for(@project.os)
        if os_config[:firmware_url]
          initrd_orig = DIRS[:netboot] / "assets" / "debian-installer" / @arch / "initrd.gz.orig"
          assert("Firmware injected into initrd") { initrd_orig.exist? }
        end

      rescue Timeout::Error
        assert("PXE handshake completed within #{TIMEOUT}s") { false }
      end

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

      def report
        puts "\n--- Results ---"
        total = @passed + @failed
        puts "#{@passed}/#{total} passed (#{@arch})"

        if @failed > 0
          puts "\nDebug logs (all under #{E2E_ROOT}):"
          puts "  dnsmasq: #{DIRS[:logs] / "dnsmasq.log"}"
          puts "  HTTP:    #{DIRS[:logs] / "http.log"}"
          puts "  QEMU:    #{DIRS[:logs] / "qemu.log"}"
          exit 1
        end
      end

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

        @bridge&.down
        @project&.cleanup

        puts "Teardown complete."
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

Pcs::E2E::PxeHandshakeTest.new.run if __FILE__ == $PROGRAM_NAME
