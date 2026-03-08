---
---

# Plan 1C: Extract Arch + OS Data to Gem

**Tier:** E2E
**Objective:** Move architecture and OS installer data out of test code and into the gem as YAML data files under `lib/pcs/platform/`. Split the current `ArchConfig` into two concerns: architecture (QEMU/hardware) and operating system (installer/preseed). NetbootService and e2e tests both consume from the same source. Adding a new arch or OS becomes a YAML edit, not a code change.
**Depends on:** Plan 1B (Multi-Architecture Support)
**Required before:** Plan 2 (PXE Handshake)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/e2e/README.md` — tier overview
- `lib/pcs/platform.rb` — platform detection module
- `lib/pcs/platform/base.rb`, `lib/pcs/platform/linux.rb`, `lib/pcs/platform/darwin.rb` — existing platform classes
- `lib/pcs/services/netboot_service.rb` — generates boot assets, currently hardcodes Debian installer URLs via service config
- `spec/e2e/support/arch_config.rb` — current e2e ArchConfig (to be replaced)
- `spec/e2e/support/qemu_launcher.rb` — uses ArchConfig
- `spec/e2e/support/test_project.rb` — uses ArchConfig for installer URLs

---

## What This Plan Builds

### New file: `lib/pcs/platform/architectures.yml`

Pure QEMU/hardware data. No OS-specific values.

```yaml
amd64:
  qemu_binary: qemu-system-x86_64
  machine: q35
  cpu_kvm: host
  cpu_tcg: qemu64
  nic_model: virtio-net-pci
  uefi_firmware:
  ipxe_boot_file: netboot.xyz.efi
  pxe_service_tag: x86-64_EFI

arm64:
  qemu_binary: qemu-system-aarch64
  machine: virt
  cpu_kvm: host
  cpu_tcg: cortex-a72
  nic_model: virtio-net-pci
  uefi_firmware: /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
  ipxe_boot_file: netboot.xyz-arm64.efi
  pxe_service_tag: ARM64_EFI
```

### New file: `lib/pcs/platform/operating_systems.yml`

OS installer data. Each entry has a `family`, `preseed_format`, `mirror`, and per-arch `installer` paths. The paths are relative to the mirror — the full URL is composed at runtime.

```yaml
debian-bookworm:
  family: debian
  version: "12"
  codename: bookworm
  mirror: http://deb.debian.org/debian
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
  preseed_format: preseed
  installer:
    amd64:
      kernel_path: dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux
      initrd_path: dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz
    arm64:
      kernel_path: dists/trixie/main/installer-arm64/current/images/netboot/debian-installer/arm64/linux
      initrd_path: dists/trixie/main/installer-arm64/current/images/netboot/debian-installer/arm64/initrd.gz
```

### New file: `lib/pcs/platform/arch.rb`

Loads `architectures.yml`. Provides arch lookup, native detection, KVM check.

```ruby
# frozen_string_literal: true

require "yaml"
require "pathname"

module Pcs
  module Platform
    module Arch
      YAML_PATH = Pathname.new(__dir__).join("architectures.yml").freeze
      SUPPORTED = %w[amd64 arm64].freeze

      class << self
        def config_for(arch)
          configs.fetch(arch) { raise "Unsupported architecture: #{arch}. Supported: #{SUPPORTED.join(", ")}" }
        end

        def configs
          @configs ||= YAML.safe_load_file(YAML_PATH, symbolize_names: true)
        end

        def native
          case RUBY_PLATFORM
          when /aarch64|arm64/ then "arm64"
          when /x86_64|x64/    then "amd64"
          else raise "Unknown host architecture: #{RUBY_PLATFORM}"
          end
        end

        def resolve(requested)
          return native if requested.nil? || requested.empty?
          raise "Unsupported architecture: #{requested}" unless SUPPORTED.include?(requested)

          requested
        end

        def kvm_available?(arch)
          File.exist?("/dev/kvm") && arch == native
        end

        def verify_dependencies!(arch)
          cfg = config_for(arch)

          unless system("command -v #{cfg[:qemu_binary]} > /dev/null 2>&1")
            raise "#{cfg[:qemu_binary]} not found. Install the appropriate qemu-system package."
          end

          if cfg[:uefi_firmware] && !File.exist?(cfg[:uefi_firmware])
            raise "UEFI firmware not found at #{cfg[:uefi_firmware]}. Install with: sudo apt-get install -y qemu-efi-aarch64"
          end
        end

        def reset!
          @configs = nil
        end
      end
    end
  end
end
```

### New file: `lib/pcs/platform/os.rb`

Loads `operating_systems.yml`. Provides OS lookup and URL composition.

```ruby
# frozen_string_literal: true

require "yaml"
require "pathname"

module Pcs
  module Platform
    module Os
      YAML_PATH = Pathname.new(__dir__).join("operating_systems.yml").freeze

      class << self
        def config_for(os_name)
          configs.fetch(os_name) { raise "Unknown OS: #{os_name}. Available: #{configs.keys.join(", ")}" }
        end

        def configs
          @configs ||= YAML.safe_load_file(YAML_PATH, symbolize_names: true)
        end

        def available
          configs.keys.map(&:to_s)
        end

        # Returns { kernel_path:, initrd_path: } for a specific arch
        def installer_for(os_name, arch)
          os = config_for(os_name)
          installers = os[:installer] || {}
          arch_key = arch.to_sym

          unless installers.key?(arch_key)
            raise "OS '#{os_name}' has no installer for arch '#{arch}'. Available: #{installers.keys.join(", ")}"
          end

          installers[arch_key]
        end

        # Compose full URLs for kernel and initrd
        def installer_urls(os_name, arch)
          os = config_for(os_name)
          paths = installer_for(os_name, arch)
          mirror = os[:mirror]

          {
            kernel_url: "#{mirror}/#{paths[:kernel_path]}",
            initrd_url: "#{mirror}/#{paths[:initrd_path]}"
          }
        end

        def reset!
          @configs = nil
        end
      end
    end
  end
end
```

### Modify: `lib/pcs/platform.rb`

Add requires for the new modules.

```ruby
# frozen_string_literal: true

module Pcs
  module Platform
    def self.current
      @current ||= load_platform
    end

    def self.reset!
      @current = nil
    end

    def self.load_platform
      case RUBY_PLATFORM
      when /darwin/
        require_relative "platform/darwin"
        Darwin.new
      when /linux/
        require_relative "platform/linux"
        Linux.new
      else
        raise "Unsupported platform: #{RUBY_PLATFORM}"
      end
    end

    private_class_method :load_platform
  end
end

require_relative "platform/arch"
require_relative "platform/os"
```

### Modify: `lib/pcs/services/netboot_service.rb`

Replace hardcoded installer URLs with `Platform::Os` lookups. In `download_boot_files`, instead of reading URLs from the service record:

```ruby
def self.download_boot_files(config:, system_cmd:, arch: "amd64", os: "debian-bookworm")
  urls = Platform::Os.installer_urls(os, arch)
  os_config = Platform::Os.config_for(os)
  installer_paths = Platform::Os.installer_for(os, arch)

  # Use os_config[:installer][arch.to_sym] for the subdir
  dest_dir = netboot_dir / "assets" / os_config[:installer][arch.to_sym][:kernel_path].split("/")[0..1].join("/") rescue netboot_dir / "assets" / "installer"
  # Simpler: use a consistent subdir based on os and arch
  dest_dir = netboot_dir / "assets" / "#{os}-#{arch}"
  system_cmd.run!("mkdir -p #{dest_dir}", sudo: true)

  kernel_path = dest_dir / "linux"
  initrd_path = dest_dir / "initrd.gz"

  [[urls[:kernel_url], kernel_path], [urls[:initrd_url], initrd_path]].each do |url, path|
    if path.exist?
      puts "  -> #{path.basename} already present"
    else
      puts "  -> Downloading #{path.basename}..."
      system_cmd.run!("wget -q -O #{path} #{url}", sudo: true)
    end
  end
end
```

**Note:** The exact refactor of `download_boot_files` depends on how the current service config (`debian_kernel`, `debian_initrd` from the Service record) should coexist with the new `Platform::Os` data. The recommended approach:

- `Platform::Os` provides the **defaults** — the canonical URLs for each OS+arch
- The Service record in `data/services.yml` can **override** specific URLs (e.g., to point at a local mirror)
- If the Service record has `debian_kernel` set, use it; otherwise fall back to `Platform::Os`

This preserves backward compatibility while making the common case (standard mirrors) zero-config.

### Modify: `spec/e2e/support/arch_config.rb` → DELETE

Remove entirely. Replace all references with `Pcs::Platform::Arch`.

### Modify: `spec/e2e/support/qemu_launcher.rb`

Replace:
```ruby
require_relative "arch_config"
# ...
ArchConfig.native_arch
ArchConfig.config_for(arch)
ArchConfig.kvm_available?(arch)
ArchConfig.verify_dependencies!(arch)
```

With:
```ruby
require "pcs/platform/arch"
# ...
Pcs::Platform::Arch.native
Pcs::Platform::Arch.config_for(arch)
Pcs::Platform::Arch.kvm_available?(arch)
Pcs::Platform::Arch.verify_dependencies!(arch)
```

### Modify: `spec/e2e/support/test_project.rb`

Replace `ArchConfig` references with `Platform::Arch` and `Platform::Os`. The test project should accept both `arch:` and `os:` parameters (defaulting to `"debian-bookworm"`).

In `write_service_data`, instead of embedding URLs from ArchConfig:

```ruby
def write_service_data
  data_dir = @base_dir / "data"
  data_dir.mkpath

  urls = Pcs::Platform::Os.installer_urls(@os, @arch)

  services_yml = {
    "records" => [
      {
        "name" => "netbootxyz",
        "image" => "docker.io/netbootxyz/netbootxyz",
        "debian_kernel" => urls[:kernel_url],
        "debian_initrd" => urls[:initrd_url],
        "ipxe_timeout" => 10
      }
    ]
  }

  (data_dir / "services.yml").write(YAML.dump(services_yml))
end
```

---

## Implementation Spec

1. Create `lib/pcs/platform/architectures.yml`
2. Create `lib/pcs/platform/operating_systems.yml`
3. Create `lib/pcs/platform/arch.rb` — loads YAML, provides `config_for`, `native`, `resolve`, `kvm_available?`, `verify_dependencies!`
4. Create `lib/pcs/platform/os.rb` — loads YAML, provides `config_for`, `installer_for`, `installer_urls`, `available`
5. Modify `lib/pcs/platform.rb` — add requires for `arch` and `os`
6. Modify `lib/pcs/services/netboot_service.rb` — use `Platform::Os.installer_urls` as defaults for download URLs (backward compatible with service record overrides)
7. Delete `spec/e2e/support/arch_config.rb`
8. Modify `spec/e2e/support/qemu_launcher.rb` — replace `ArchConfig` → `Pcs::Platform::Arch`
9. Modify `spec/e2e/support/test_project.rb` — replace `ArchConfig` → `Pcs::Platform::Arch` + `Pcs::Platform::Os`, add `os:` parameter
10. Run existing specs — all should pass (backward compatible)

---

## Verification

```bash
# 1. Arch lookup
ruby -e '
  require_relative "lib/pcs/platform/arch"
  puts Pcs::Platform::Arch.native
  pp Pcs::Platform::Arch.config_for("amd64")
  pp Pcs::Platform::Arch.config_for("arm64")
'

# 2. OS lookup
ruby -e '
  require_relative "lib/pcs/platform/os"
  pp Pcs::Platform::Os.available
  pp Pcs::Platform::Os.installer_urls("debian-bookworm", "arm64")
  pp Pcs::Platform::Os.installer_urls("debian-trixie", "amd64")
'

# 3. Composed lookup (what NetbootService would do)
ruby -e '
  require_relative "lib/pcs/platform/arch"
  require_relative "lib/pcs/platform/os"
  arch = Pcs::Platform::Arch.native
  os = "debian-bookworm"
  urls = Pcs::Platform::Os.installer_urls(os, arch)
  puts "#{os} on #{arch}:"
  puts "  kernel: #{urls[:kernel_url]}"
  puts "  initrd: #{urls[:initrd_url]}"
'

# 4. Existing specs still pass
bundle exec rspec

# 5. E2E harness still works (QemuLauncher, TestProject)
ruby -e '
  require_relative "spec/e2e/support/e2e_root"
  require_relative "spec/e2e/support/test_bridge"
  require_relative "spec/e2e/support/qemu_launcher"
  arch = Pcs::Platform::Arch.native
  q = Pcs::E2E::QemuLauncher.new(arch: arch)
  puts "OK: QemuLauncher constructed for #{arch}"
'
```
