---
---

# Plan 2: PXE Handshake — Firmware Injection + Boot Pipeline Validation

**Tier:** E2E
**Objective:** Add firmware injection to `Platform::Os` and `NetbootService`, then validate the full PXE boot pipeline — a QEMU VM PXE boots, gets a DHCP offer, downloads the iPXE menu, and reaches the Debian installer kernel with firmware-enriched initrd. Stop before the actual install.
**Depends on:** Plan 1C (Arch + OS Data)
**Required before:** Plan 3 (Full Install)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/e2e/README.md` — tier overview, network layout, filesystem layout
- `docs/e2e/plan-01-test-harness.md` — harness classes (TestBridge, QemuLauncher, TestProject, E2E_ROOT)
- `docs/e2e/plan-01b-multi-arch.md` — multi-arch QemuLauncher and TestProject
- `docs/e2e/plan-01c-arch-os-data.md` — Platform::Arch and Platform::Os in the gem
- `lib/pcs/platform/arch.rb` — architecture configs loaded from YAML
- `lib/pcs/platform/os.rb` — OS configs loaded from YAML
- `lib/pcs/platform/operating_systems.yml` — OS data (to be extended with firmware_url)
- `lib/pcs/services/netboot_service.rb` — generates iPXE menus, preseed, post-install scripts; `download_boot_files` fetches kernel + initrd
- `lib/pcs/templates/dnsmasq/pcs-pxe-proxy.conf.erb` — dnsmasq PXE proxy config template
- `spec/e2e/support/*.rb` — harness classes from plan-01, 01b, 01c

---

## What This Plan Builds

### Part A: Firmware Injection

Some hardware (especially newer NICs and storage controllers) requires non-free firmware that is not included in the standard Debian installer initrd. Debian provides a `firmware.cpio.gz` archive per release that can be concatenated onto the initrd. This is the standard Debian mechanism for injecting firmware into the installer.

#### Modify: `lib/pcs/platform/operating_systems.yml`

Add optional `firmware_url` field. Only Debian-family OSes that need it will have it set. RHEL-family installers include firmware in their images, so the field is absent (or null).

```yaml
debian-bookworm:
  family: debian
  version: "12"
  codename: bookworm
  mirror: http://deb.debian.org/debian
  firmware_url: https://cdimage.debian.org/cdimage/firmware/bookworm/current/firmware.cpio.gz
  preseed_format: preseed
  installer:
    amd64:
      kernel_path: dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux
      initrd_path: dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz
    arm64:
      kernel_path: dists/bookworm/main/installer-arm64/current/images/netboot/debian-installer/arm64/linux
      initrd_path: dists/bookworm/main/installer-arm64/current/images/netboot/debian-installer/arm64/initrd.gz

debian-trixie:
  family: debian
  version: "13"
  codename: trixie
  mirror: http://deb.debian.org/debian
  firmware_url: https://cdimage.debian.org/cdimage/firmware/trixie/current/firmware.cpio.gz
  preseed_format: preseed
  installer:
    amd64:
      kernel_path: dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux
      initrd_path: dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz
    arm64:
      kernel_path: dists/trixie/main/installer-arm64/current/images/netboot/debian-installer/arm64/linux
      initrd_path: dists/trixie/main/installer-arm64/current/images/netboot/debian-installer/arm64/initrd.gz
```

#### Modify: `lib/pcs/platform/os.rb`

Add a helper to retrieve the firmware URL:

```ruby
def firmware_url(os_name)
  os = config_for(os_name)
  os[:firmware_url]  # nil if not set — caller checks before downloading
end
```

#### Modify: `lib/pcs/services/netboot_service.rb`

In `download_boot_files`, after downloading the kernel and initrd, check for firmware and inject it:

```ruby
def self.download_boot_files(config:, system_cmd:, arch: "amd64", os: "debian-bookworm")
  urls = Platform::Os.installer_urls(os, arch)

  dest_dir = netboot_dir / "assets" / Platform::Os.installer_for(os, arch)[:kernel_path].split("/")[0..3].join("/")
  # Or simpler consistent path:
  dest_dir = netboot_dir / "assets" / "debian-installer" / arch
  system_cmd.run!("mkdir -p #{dest_dir}", sudo: true)

  kernel_path = dest_dir / "linux"
  initrd_path = dest_dir / "initrd.gz"

  # Download kernel
  download_file(urls[:kernel_url], kernel_path, system_cmd: system_cmd)

  # Download initrd
  download_file(urls[:initrd_url], initrd_path, system_cmd: system_cmd)

  # Inject firmware if available for this OS
  inject_firmware(os: os, initrd_path: initrd_path, system_cmd: system_cmd)
end

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
```

**Key design decisions:**

- `firmware.cpio.gz` is downloaded once and cached alongside the initrd — same idempotent pattern as kernel/initrd downloads
- The original initrd is backed up as `initrd.gz.orig` so firmware injection is re-runnable (won't double-concatenate)
- `inject_firmware` is a no-op when `firmware_url` is nil — RHEL-family or any OS without a firmware archive just skips it
- The concatenation approach (`cat initrd.gz.orig firmware.cpio.gz > initrd.gz`) is the standard Debian mechanism — the installer's initramfs unpacks multiple cpio archives in sequence

**Idempotency note:** If `initrd.gz.orig` already exists, the injection has already been done. The method should check for this:

```ruby
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
```

---

### Part B: PXE Handshake Test

A single test file that validates the PXE boot pipeline up to (but not including) the OS install. Architecture-aware: uses native arch by default (arm64 with KVM on RPi), respects `PCS_E2E_ARCH` env var for override. The initrd served to the VM now includes firmware.

### File: `spec/e2e/pxe_handshake_test.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# PXE Handshake E2E Test
#
# Validates: dnsmasq DHCP offer → iPXE download → PCS menu chain → kernel download
# Runtime: ~30 seconds (KVM) / ~60 seconds (TCG)
# Requires: Linux, sudo, qemu-system-{aarch64,x86_64}, dnsmasq-base

require "open3"
require "pathname"
require "timeout"
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

        puts "Generating netboot configs..."
        Dir.chdir(project_dir) do
          Pcs.boot!(project_dir: project_dir)
          site = Pcs::Site.load(TestProject::SITE_NAME)
          config = Pcs.config
          Pcs::Services::NetbootService.reload(config: config, site: site)
        end

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
        os = @project.os
        os_config = Pcs::Platform::Os.config_for(os)
        if os_config[:firmware_url]
          installer = Pcs::Platform::Os.installer_for(os, @arch)
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

        @qemu.stop if @qemu.running?

        if @dnsmasq_pid
          Process.kill("TERM", @dnsmasq_pid) rescue nil
          Process.wait(@dnsmasq_pid) rescue nil
        end

        if @netboot_pid
          Process.kill("TERM", @netboot_pid) rescue nil
          Process.wait(@netboot_pid) rescue nil
        end

        @bridge.down
        @project.cleanup

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
```

---

## Implementation Spec

### Part A: Firmware injection

1. Add `firmware_url` field to `debian-bookworm` and `debian-trixie` in `lib/pcs/platform/operating_systems.yml`
2. Add `firmware_url(os_name)` method to `lib/pcs/platform/os.rb`
3. Add `inject_firmware` private method to `lib/pcs/services/netboot_service.rb`
4. Extract `download_file` helper in `NetbootService` (DRY up kernel/initrd/firmware downloads)
5. Call `inject_firmware` at the end of `download_boot_files`
6. Idempotency: check for `initrd.gz.orig` — if present, firmware was already injected

### Part B: PXE handshake test

7. Create `spec/e2e/pxe_handshake_test.rb`
8. Resolve arch from `PCS_E2E_ARCH` env var via `Platform::Arch.resolve` (defaults to native)
9. Verify dependencies for the resolved arch before proceeding
10. Pass `arch:` to `QemuLauncher.new` and `TestProject.new`
11. Use `@arch_config[:ipxe_boot_file]` in the dnsmasq `dhcp-boot` directive
12. Add assertion: `initrd.gz.orig` exists (firmware was injected)
13. Expose `os` accessor on `TestProject` so the test can check firmware_url for the OS
14. Report arch and KVM/TCG status in output

### Architecture-dependent dnsmasq config

The only line that changes between arches is the boot file:

- amd64: `dhcp-boot=netboot.xyz.efi,,10.99.0.1`
- arm64: `dhcp-boot=netboot.xyz-arm64.efi,,10.99.0.1`

Everything else (bridge, DHCP range, TFTP root) is identical.

---

## Verification

```bash
# Part A: Firmware injection
ruby -e '
  require_relative "lib/pcs/platform/os"
  puts Pcs::Platform::Os.firmware_url("debian-trixie")
  # => https://cdimage.debian.org/cdimage/firmware/trixie/current/firmware.cpio.gz
  puts Pcs::Platform::Os.firmware_url("debian-bookworm")
  # => https://cdimage.debian.org/cdimage/firmware/bookworm/current/firmware.cpio.gz
'

# Part B: PXE handshake
# On RPi (arm64, fast):
bin/e2e handshake
# => Architecture: arm64 (KVM)
# => ...
# =>   ✓ Firmware injected into initrd
# => 7/7 passed (arm64)

# Explicit amd64 (slow, TCG):
bin/e2e handshake --arch amd64
# => Architecture: amd64 (TCG)
# => 7/7 passed (amd64)
```
