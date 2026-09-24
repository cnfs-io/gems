---
---

# Plan 04 — Netboot Platform-Only

## Context

Read before starting:
- `lib/pcs/service/netbootxyz.rb` — the file to clean up (renamed in plan-03)
- `lib/pcs/platform/os.rb` — `Platform::Os.installer_urls(os_name, arch)` and `Platform::Os.firmware_url(os_name)`
- `lib/pcs/platform/arch.rb` — `Platform::Arch.native` for default arch detection
- `lib/pcs/platform/operating_systems.yml` — OS definitions with per-arch installer paths
- `lib/pcs/config.rb` — `config.service.netbootxyz` has image and ipxe_timeout (from plan-02)

## Background

After plan-02, the `Service.definition("netbootxyz")` calls were replaced with `Pcs.config.service.netbootxyz` for image and ipxe_timeout. However, `download_boot_files` may still have vestiges of the old pattern or hardcoded defaults. This plan ensures the method is clean and uses `Platform::Os` as the single source of truth for installer URLs.

Additionally, `download_boot_files` currently has hardcoded defaults of `arch: "amd64"` and `os: "debian-bookworm"`. These should be configurable or at minimum use sensible defaults from Platform::Arch.

## Implementation

### Step 1: Review and clean download_boot_files

In `lib/pcs/service/netbootxyz.rb`, ensure `download_boot_files` looks like:

```ruby
def self.download_boot_files(system_cmd:, arch: Platform::Arch.native, os: "debian-trixie")
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

  puts "  -> Installer files ready in #{dest_dir}"
end
```

Key changes:
- Default arch uses `Platform::Arch.native` instead of hardcoded `"amd64"`
- Default OS is `"debian-trixie"` (current target, was `"debian-bookworm"`)
- No `Service.definition` fallback — `Platform::Os` is the only source
- No references to `svc_def`, `debian_kernel`, `debian_initrd`

### Step 2: Verify no Service model references remain

Search the entire netbootxyz file for any remaining references to:
- `Pcs::Service` (the old model)
- `Service.definition`
- `svc_def`
- `debian_kernel` / `debian_initrd` (as config attributes)

Remove any that remain.

### Step 3: Consider adding OS default to config DSL

Optionally, add a default OS to the netbootxyz config:

In `lib/pcs/config.rb`, add to `NetbootxyzSettings`:
```ruby
class NetbootxyzSettings
  attr_accessor :image, :ipxe_timeout, :default_os

  def initialize
    @image = "docker.io/netbootxyz/netbootxyz"
    @ipxe_timeout = 10
    @default_os = "debian-trixie"
  end
end
```

Then in `download_boot_files`:
```ruby
def self.download_boot_files(system_cmd:, arch: Platform::Arch.native, os: nil)
  os ||= Pcs.config.service.netbootxyz.default_os
  # ...
end
```

This keeps the OS target configurable in `pcs.rb` without hardcoding it in the service class.

### Step 4: Clean up generate_pxe_files

Verify `generate_pxe_files` uses only `Pcs.config.service.netbootxyz.ipxe_timeout` and has no `Service.definition` references.

## Test Spec

### New/updated specs

```ruby
RSpec.describe Pcs::Service::Netbootxyz do
  describe ".download_boot_files" do
    it "uses Platform::Os for installer URLs" do
      # Verify Platform::Os.installer_urls is called, not Service.definition
    end

    it "defaults to native architecture" do
      # Verify Platform::Arch.native is used as default
    end

    it "defaults to configured OS" do
      # Verify Pcs.config.service.netbootxyz.default_os is used
    end
  end
end
```

### Verify no old patterns
- `grep -r "Service\.definition\|svc_def\|debian_kernel\|debian_initrd" lib/` returns empty
- `grep -r "debian-bookworm" lib/pcs/service/` returns empty (default changed to trixie)

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
grep -r "Service\.definition\|svc_def" lib/
grep -r "debian_kernel\|debian_initrd" lib/
```

All greps empty. All specs green.
