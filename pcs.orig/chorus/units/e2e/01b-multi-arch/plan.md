---
---

# Plan 1B: Multi-Architecture Support

**Tier:** E2E
**Objective:** Make the e2e harness architecture-aware so it can run arm64 guests with KVM on the RPi (fast, ~3-5 min) or amd64 guests via TCG (slow, ~10-15 min). Default to native arch for speed; allow explicit override.
**Depends on:** Plan 1 (Test Harness)
**Required before:** Plan 2 (PXE Handshake)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/e2e/README.md` — tier overview, architecture
- `docs/e2e/plan-01-test-harness.md` — original harness (what was implemented)
- `spec/e2e/support/qemu_launcher.rb` — current implementation (hardcodes `qemu-system-x86_64`)
- `spec/e2e/support/test_project.rb` — current implementation (hardcodes amd64 installer URLs)
- `spec/e2e/support/e2e_root.rb` — E2E_ROOT, DIRS
- `bin/e2e` — current runner (hardcodes `qemu-system-x86_64` in pre-flight check)

---

## What This Plan Changes

### 1. New file: `test/e2e/support/arch_config.rb`

Centralizes all architecture-dependent values in one place.

```ruby
# frozen_string_literal: true

module Pcs
  module E2E
    module ArchConfig
      SUPPORTED = %w[amd64 arm64].freeze

      CONFIGS = {
        "amd64" => {
          qemu_binary: "qemu-system-x86_64",
          machine: "q35",
          cpu_kvm: "host",
          cpu_tcg: "qemu64",
          nic_model: "virtio-net-pci",
          debian_kernel_url: "http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux",
          debian_initrd_url: "http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz",
          installer_subdir: "debian-installer/amd64",
          ipxe_boot_file: "netboot.xyz.efi",
          pxe_service_tag: "x86-64_EFI"
        },
        "arm64" => {
          qemu_binary: "qemu-system-aarch64",
          machine: "virt",
          cpu_kvm: "host",
          cpu_tcg: "cortex-a72",
          nic_model: "virtio-net-pci",
          uefi_firmware: "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd",
          debian_kernel_url: "http://deb.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/debian-installer/arm64/linux",
          debian_initrd_url: "http://deb.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/debian-installer/arm64/initrd.gz",
          installer_subdir: "debian-installer/arm64",
          ipxe_boot_file: "netboot.xyz-arm64.efi",
          pxe_service_tag: "ARM64_EFI"
        }
      }.freeze

      # Detect native arch of the host
      def self.native_arch
        case RUBY_PLATFORM
        when /aarch64|arm64/ then "arm64"
        when /x86_64|x64/    then "amd64"
        else raise "Unknown host architecture: #{RUBY_PLATFORM}"
        end
      end

      # Resolve requested arch: nil => native, "both" kept as-is for runner
      def self.resolve(requested)
        return native_arch if requested.nil?
        return requested if SUPPORTED.include?(requested)

        raise "Unsupported architecture: #{requested}. Supported: #{SUPPORTED.join(", ")}"
      end

      def self.config_for(arch)
        CONFIGS.fetch(arch) { raise "No config for arch: #{arch}" }
      end

      # Can we use KVM for this arch on this host?
      def self.kvm_available?(arch)
        File.exist?("/dev/kvm") && arch == native_arch
      end
    end
  end
end
```

### 2. Relocate `test/e2e/` → `spec/e2e/`

Move the entire `test/e2e/` directory to `spec/e2e/` for consistency with the project's existing RSpec convention. Remove the empty `test/` directory. All subsequent file references use the new path.

### 3. Modify: `spec/e2e/support/qemu_launcher.rb`

Accept `arch:` parameter, use `ArchConfig` for binary, machine type, CPU, and UEFI firmware.

Changes to make:

- `initialize` gains `arch: ArchConfig.native_arch` parameter, stores `@arch` and `@arch_config = ArchConfig.config_for(arch)`
- `base_args` uses `@arch_config[:qemu_binary]` instead of hardcoded `"qemu-system-x86_64"`
- `base_args` uses `@arch_config[:machine]` instead of hardcoded `"q35"`
- `base_args` uses `@arch_config[:cpu_kvm]` / `@arch_config[:cpu_tcg]` instead of hardcoded `"host"` / `"qemu64"`
- KVM check uses `ArchConfig.kvm_available?(@arch)` instead of just `File.exist?("/dev/kvm")`
- For arm64: add `-bios #{@arch_config[:uefi_firmware]}` to `base_args` (aarch64 `virt` machine requires explicit UEFI firmware)
- Expose `attr_reader :arch` so tests can report which arch is running

Updated `base_args`:

```ruby
def base_args(name, ram, cpus)
  accel = ArchConfig.kvm_available?(@arch) ? "kvm" : "tcg"
  cpu = accel == "kvm" ? @arch_config[:cpu_kvm] : @arch_config[:cpu_tcg]

  args = [
    @arch_config[:qemu_binary],
    "-name", name,
    "-machine", "#{@arch_config[:machine]},accel=#{accel}",
    "-cpu", cpu,
    "-m", ram,
    "-smp", cpus,
    "-nographic",
    "-serial", "mon:stdio",
    "-nic", "tap,ifname=#{@tap},script=no,downscript=no,model=#{@arch_config[:nic_model]}"
  ]

  # arm64 virt machine requires explicit UEFI firmware
  if @arch_config[:uefi_firmware]
    args += ["-bios", @arch_config[:uefi_firmware]]
  end

  args
end
```

### 4. Modify: `spec/e2e/support/test_project.rb`

Accept `arch:` parameter to write the correct Debian installer URLs in service data.

Changes to make:

- `initialize` gains `arch: ArchConfig.native_arch` parameter, stores `@arch` and `@arch_config = ArchConfig.config_for(arch)`
- `write_service_data` uses `@arch_config[:debian_kernel_url]` and `@arch_config[:debian_initrd_url]`
- `write_host_data` uses `@arch_config` for the `arch` field on the host record

Updated `write_service_data`:

```ruby
def write_service_data
  data_dir = @base_dir / "data"
  data_dir.mkpath

  services_yml = {
    "records" => [
      {
        "name" => "netbootxyz",
        "image" => "docker.io/netbootxyz/netbootxyz",
        "debian_kernel" => @arch_config[:debian_kernel_url],
        "debian_initrd" => @arch_config[:debian_initrd_url],
        "ipxe_timeout" => 10
      }
    ]
  }

  (data_dir / "services.yml").write(YAML.dump(services_yml))
end
```

Updated `write_host_data` — add `"arch" => @arch` to the host record.

### 5. Modify: `bin/e2e`

Accept `--arch` flag. Pass it through to the Ruby test as an environment variable.

```bash
#!/usr/bin/env bash
set -euo pipefail

# E2E test runner for PCS bootstrap pipeline
# Usage: bin/e2e [tier] [--arch ARCH]
#   tier: handshake | full (default: handshake)
#   arch: amd64 | arm64 | both (default: native)

TIER="handshake"
ARCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="$2"
      shift 2
      ;;
    handshake|full)
      TIER="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bin/e2e [handshake|full] [--arch amd64|arm64|both]"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GEM_DIR="$(dirname "$SCRIPT_DIR")"

if [[ "$(uname)" != "Linux" ]]; then
  echo "Error: E2E tests require Linux (bridge/tap networking)."
  echo "Run on the RPi or a Linux dev VM."
  exit 1
fi

# Check that at least one qemu binary is available
if ! command -v qemu-system-x86_64 &>/dev/null && ! command -v qemu-system-aarch64 &>/dev/null; then
  echo "Error: No QEMU system emulator found. Install with:"
  echo "  sudo apt-get install -y qemu-system-arm qemu-system-x86 qemu-system-data"
  exit 1
fi

for cmd in ip dnsmasq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd not found. Install with:"
    echo "  sudo apt-get install -y dnsmasq-base bridge-utils iproute2"
    exit 1
  fi
done

cleanup() {
  echo
  echo "=== Teardown ==="
  cd "$GEM_DIR" && bundle exec ruby spec/e2e/teardown.rb 2>/dev/null || true
}
trap cleanup EXIT

run_test() {
  local tier="$1"
  local arch="$2"

  echo "=== PCS E2E Test Runner (tier: $tier, arch: $arch) ==="
  echo

  export PCS_E2E_ARCH="$arch"

  cd "$GEM_DIR"
  case "$tier" in
    handshake)
      bundle exec ruby spec/e2e/pxe_handshake_test.rb
      ;;
    full)
      bundle exec ruby spec/e2e/full_install_test.rb
      ;;
  esac
}

if [[ "$ARCH" == "both" ]]; then
  run_test "$TIER" "arm64"
  run_test "$TIER" "amd64"
elif [[ -n "$ARCH" ]]; then
  run_test "$TIER" "$ARCH"
else
  # Empty ARCH means auto-detect in Ruby
  run_test "$TIER" ""
fi
```

### 6. Tests read arch from environment

Both `spec/e2e/pxe_handshake_test.rb` and `spec/e2e/full_install_test.rb` (plans 02 and 03) should resolve arch at startup:

```ruby
arch = ArchConfig.resolve(ENV.fetch("PCS_E2E_ARCH", nil))
puts "  Architecture: #{arch} (#{ArchConfig.kvm_available?(arch) ? "KVM" : "TCG"})"
```

Then pass `arch:` when constructing `QemuLauncher.new(arch: arch)` and `TestProject.new(arch: arch)`.

### 7. UEFI firmware dependency for arm64

arm64 QEMU with the `virt` machine requires UEFI firmware. On Debian/Ubuntu:

```bash
sudo apt-get install -y qemu-efi-aarch64
```

This provides `/usr/share/qemu-efi-aarch64/QEMU_EFI.fd`. The pre-flight check in `bin/e2e` should verify this file exists when running arm64.

Add to `ArchConfig`:

```ruby
def self.verify_dependencies!(arch)
  cfg = config_for(arch)

  # Check QEMU binary
  unless system("command -v #{cfg[:qemu_binary]} > /dev/null 2>&1")
    raise "#{cfg[:qemu_binary]} not found. Install the appropriate qemu-system package."
  end

  # Check UEFI firmware for arm64
  if cfg[:uefi_firmware] && !File.exist?(cfg[:uefi_firmware])
    raise "UEFI firmware not found at #{cfg[:uefi_firmware]}. Install with: sudo apt-get install -y qemu-efi-aarch64"
  end
end
```

Call this early in each test's `setup` method.

---

## Implementation Spec

1. Create `spec/e2e/support/arch_config.rb`
2. Move `test/e2e/` → `spec/e2e/`, remove empty `test/` directory
3. Modify `spec/e2e/support/qemu_launcher.rb`:
   - Add `arch:` param to `initialize`
   - Replace all hardcoded x86 values with `@arch_config` lookups
   - Add UEFI firmware arg for arm64
4. Modify `spec/e2e/support/test_project.rb`:
   - Add `arch:` param to `initialize`
   - Use arch-specific Debian installer URLs
   - Set `arch` field on host record
5. Rewrite `bin/e2e`:
   - Parse `--arch` flag
   - Export `PCS_E2E_ARCH` env var
   - Support `--arch both` to run sequentially
   - Check for any QEMU binary (not just x86_64)
6. Update `spec/e2e/teardown.rb` — no changes needed (arch-agnostic)

---

## Verification

```bash
# On RPi (arm64):

# 1. Native arch detection
ruby -e '
  require_relative "test/e2e/support/arch_config"
  puts Pcs::E2E::ArchConfig.native_arch
  # => arm64
'

# 2. KVM available for native
ruby -e '
  require_relative "test/e2e/support/arch_config"
  puts Pcs::E2E::ArchConfig.kvm_available?("arm64")
  # => true (on RPi with /dev/kvm)
  puts Pcs::E2E::ArchConfig.kvm_available?("amd64")
  # => false (cross-arch, TCG only)
'

# 3. Dependency check
ruby -e '
  require_relative "test/e2e/support/arch_config"
  Pcs::E2E::ArchConfig.verify_dependencies!("arm64")
  puts "OK: arm64 deps satisfied"
'

# 4. QEMU launches with correct binary
ruby -e '
  require_relative "test/e2e/support/e2e_root"
  require_relative "test/e2e/support/test_bridge"
  require_relative "test/e2e/support/arch_config"
  require_relative "test/e2e/support/qemu_launcher"
  Pcs::E2E.setup_dirs!
  q = Pcs::E2E::QemuLauncher.new(arch: "arm64")
  puts "Binary: qemu-system-aarch64, KVM: #{Pcs::E2E::ArchConfig.kvm_available?("arm64")}"
  # Don't actually start — just verify construction works
  Pcs::E2E.cleanup!
'

# 5. Runner arch flag
bin/e2e handshake --arch arm64    # fast, KVM
bin/e2e handshake --arch amd64    # slow, TCG
bin/e2e handshake                 # auto-detect, arm64 on RPi
bin/e2e full --arch both          # run both sequentially
```
