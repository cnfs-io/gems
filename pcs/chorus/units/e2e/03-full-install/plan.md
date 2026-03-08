---
---

# Plan 3: Full Install — Preseed to SSH Verification

**Tier:** E2E
**Objective:** Complete a full Debian preseed install via PXE boot on the isolated test bridge, then SSH into the resulting VM and verify that the hostname, IP, SSH keys, and post-install artifacts are all correct.
**Depends on:** Plan 2 (PXE Handshake)
**Required before:** Nothing — this is the final plan in the e2e tier.

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/e2e/README.md` — tier overview, network layout, filesystem layout
- `docs/e2e/plan-01-test-harness.md` — harness classes, E2E_ROOT, DIRS
- `docs/e2e/plan-01b-multi-arch.md` — multi-arch QemuLauncher and TestProject
- `docs/e2e/plan-01c-arch-os-data.md` — Platform::Arch and Platform::Os in the gem
- `lib/pcs/platform/arch.rb` — architecture configs loaded from YAML
- `lib/pcs/platform/os.rb` — OS installer configs loaded from YAML
- `docs/e2e/plan-02-pxe-handshake.md` — PXE handshake test (setup pattern to follow)
- `lib/pcs/templates/netboot/preseed.cfg.erb` — preseed template
- `lib/pcs/templates/netboot/post-install.sh.erb` — post-install script template
- `lib/pcs/services/netboot_service.rb` — generates all boot assets (with configurable `netboot_dir`)
- `spec/e2e/support/*.rb` — harness classes from plan-01, 01b, 01c
- `spec/e2e/pxe_handshake_test.rb` — setup/teardown pattern to follow

---

## What This Plan Builds

A single test file that runs the full install pipeline and verifies the result via SSH. Architecture-aware: defaults to native arch (arm64 with KVM on RPi for ~3-5 min), supports amd64 via TCG (~10-15 min on RPi).

### File: `spec/e2e/full_install_test.rb`

```ruby
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

        puts "Generating netboot configs..."
        Dir.chdir(project_dir) do
          Pcs.boot!(project_dir: project_dir)
          site = Pcs::Site.load(TestProject::SITE_NAME)
          config = Pcs.config
          Pcs::Services::NetbootService.reload(config: config, site: site)
        end

        patch_preseed_for_test

        puts "Creating test bridge..."
        @bridge.up

        puts "Enabling NAT for internet access..."
        enable_nat

        puts "Starting dnsmasq..."
        start_dnsmasq

        puts "Starting HTTP server for boot assets..."
        start_http_server

        puts "Launching QEMU VM (PXE boot)..."
        @qemu.start_pxe(ram: "2048", disk_size: "10G")
        puts "QEMU running (pid #{@qemu.pid})"
      end

      def patch_preseed_for_test
        preseed_path = DIRS[:netboot] / "assets" / "pcs" / "preseed.cfg"
        return unless preseed_path.exist?

        content = preseed_path.read
        content.gsub!(%r{http://[\d.]+:8080/pcs}, "http://#{@bridge.bridge_ip}:8080/pcs")
        preseed_path.write(content)
      end

      def enable_nat
        cmd = Pcs::Adapters::SystemCmd.new
        result = cmd.run("ip route show default")
        @uplink = result.stdout[/dev\s+(\S+)/, 1]

        if @uplink
          cmd.run("iptables -t nat -A POSTROUTING -s 10.99.0.0/24 -o #{@uplink} -j MASQUERADE", sudo: true)
          cmd.run("iptables -A FORWARD -i #{TestBridge::BRIDGE_NAME} -o #{@uplink} -j ACCEPT", sudo: true)
          cmd.run("iptables -A FORWARD -i #{@uplink} -o #{TestBridge::BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT", sudo: true)
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

        puts "  Waiting for install to complete and VM to reboot..."
        @ssh = SshVerifier.new(
          host: TestProject::VM_STATIC_IP,
          user: "admin",
          key_path: @project.ssh_private_key_path.to_s
        )
        @ssh.wait_for_ssh(timeout: @install_timeout)
        puts "  VM is up and SSH is reachable!"

      rescue Timeout::Error => e
        puts "  TIMEOUT: #{e.message}"
        puts "  The install did not complete within #{@install_timeout}s."
        puts "  Check QEMU log: #{DIRS[:logs] / "qemu.log"}"
      end

      # ── Verification ───────────────────────────────────────

      def verify
        puts "\n--- Verification ---"

        return skip_verification("SSH not available") unless @ssh

        assert("Hostname is set correctly") do
          actual = @ssh.run("hostname")
          actual == TestProject::VM_HOSTNAME
        end

        assert("Static IP is configured") do
          output = @ssh.run("ip -4 addr show")
          output.include?(TestProject::VM_STATIC_IP)
        end

        assert("SSH authorized_keys deployed") do
          @ssh.assert_file_exists("/home/admin/.ssh/authorized_keys")
        end

        assert("Passwordless sudo configured") do
          @ssh.assert_file_exists("/etc/sudoers.d/admin")
        end

        assert("Post-install script executed") do
          @ssh.assert_file_contains("/etc/network/interfaces", TestProject::VM_STATIC_IP)
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
          puts "  ssh -i #{@project.ssh_private_key_path} -o StrictHostKeyChecking=no admin@#{TestProject::VM_STATIC_IP}"
          exit 1
        end
      end

      # ── Teardown ───────────────────────────────────────────

      def teardown
        puts "\n--- Teardown ---"

        @qemu.stop if @qemu&.running?

        if @dnsmasq_pid
          Process.kill("TERM", @dnsmasq_pid) rescue nil
          Process.wait(@dnsmasq_pid) rescue nil
        end

        if @netboot_pid
          Process.kill("TERM", @netboot_pid) rescue nil
          Process.wait(@netboot_pid) rescue nil
        end

        disable_nat
        @bridge.down
        @project.cleanup

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
```

---

## Implementation Spec

### Key differences from plan-02 (PXE Handshake):

1. **More RAM** — `2048` MB. Debian installer needs it for package extraction.
2. **Larger disk** — `10G`. Preseed partitions need room for LVM layout.
3. **NAT masquerade** — the VM needs internet access to download Debian packages. iptables rules specific to `10.99.0.0/24`, stored in `@uplink` for clean teardown.
4. **DNS via DHCP** — `dhcp-option=option:dns-server,1.1.1.1,8.8.8.8`
5. **Preseed patching** — replaces `base_url` with test bridge IP.
6. **Timeout scales with acceleration** — `KVM_INSTALL_TIMEOUT = 600` (10 min), `TCG_INSTALL_TIMEOUT = 1200` (20 min). TCG on RPi cross-compiling amd64 is slow.
7. **SSH verification** — 9 assertions including arch verification.
8. **Arch verification** — `uname -m` must match expected arch (`aarch64` for arm64, `x86_64` for amd64).

### Architecture-dependent values

| Value | amd64 | arm64 |
|-------|-------|-------|
| `dhcp-boot` | `netboot.xyz.efi` | `netboot.xyz-arm64.efi` |
| `install_timeout` | 600s (KVM) / 1200s (TCG) | 600s (KVM) / 1200s (TCG) |
| `uname -m` expected | `x86_64` | `aarch64` |
| Debian installer URLs | `installer-amd64/` | `installer-arm64/` |

### What could go wrong

| Issue | Symptom | Debug |
|-------|---------|-------|
| No KVM (cross-arch) | Install takes 15+ min | Expected on RPi with amd64 guest |
| UEFI firmware missing (arm64) | QEMU fails to start | `sudo apt-get install qemu-efi-aarch64` |
| Preseed mirror unreachable | Install hangs at packages | Check NAT rules, DNS from VM |
| Post-install script not found | VM boots but hostname/IP wrong | Check HTTP log, `installs.d/` files |
| SSH key mismatch | SSH auth fails | Verify `authorized_keys` in `DIRS[:netboot]/assets/pcs/` |

---

## Verification

```bash
# On RPi (arm64, fast — KVM):
bin/e2e full
# => Architecture: arm64 (KVM)
# => Install timeout: 600s
# => 9/9 passed (arm64, KVM)

# Explicit amd64 (slow — TCG):
bin/e2e full --arch amd64
# => Architecture: amd64 (TCG)
# => Install timeout: 1200s
# => 9/9 passed (amd64, TCG)

# Both architectures:
bin/e2e full --arch both

# Manual debugging:
ssh -i /tmp/pcs-e2e/project/.ssh/e2e_key -o StrictHostKeyChecking=no admin@10.99.0.41
cat /tmp/pcs-e2e/logs/qemu.log
cat /tmp/pcs-e2e/logs/dnsmasq.log
cat /tmp/pcs-e2e/logs/http.log
```
