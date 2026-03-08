---
---

# Plan 02: Code Organization and Model Methods

## Context

Read these files before starting:

- `lib/pim/iso.rb` — `Pim::IsoDownloader` (download, verify, iso_path)
- `lib/pim/models/iso.rb` — `Pim::Iso` FlatRecord model
- `lib/pim/models/profile.rb` — `Pim::Profile` FlatRecord model
- `lib/pim/models/build.rb` — `Pim::Build` FlatRecord model
- `lib/pim/build.rb` — `BuildConfig`, `ArchitectureResolver`, `CacheManager`, `ScriptLoader`
- `lib/pim/qemu.rb` — `Qemu` module, `QemuDiskImage`, `QemuCommandBuilder`, `QemuVM`
- `lib/pim/ssh.rb` — `SSHConnection`, `SystemSSH`
- `lib/pim/ventoy.rb` — `VentoyConfig`, `VentoyManager`
- `lib/pim/verifier.rb` — `Pim::Verifier`
- `lib/pim/http.rb` — `Pim::HTTP`

## Objective

Two concerns:

1. **Naming conventions** — each class gets its own file, named to match the class
2. **Model methods** — move operational behavior onto FlatRecord models where it belongs

## Part 1: Move ISO operations to the model

`Pim::IsoDownloader` is a thin wrapper that takes an `Iso` model and calls download/verify. This should just be methods on the model.

### Move to `lib/pim/models/iso.rb`:

```ruby
class Iso < FlatRecord::Base
  source "isos"
  read_only true
  merge_strategy :deep_merge

  attribute :name, :string
  attribute :url, :string
  attribute :checksum, :string
  attribute :checksum_url, :string
  attribute :filename, :string
  attribute :architecture, :string

  # --- Operations ---

  def download(force: false)
    filepath = iso_path

    if filepath.exist? && !force
      print "File exists. Re-download? (y/N) "
      response = $stdin.gets.chomp
      return false unless response.downcase == 'y'
    end

    puts "Downloading #{resolved_filename}..."
    Pim::HTTP.download(url, filepath.to_s)
    puts 'Verifying checksum...'
    verify
  end

  def verify(silent: false)
    filepath = iso_path

    unless filepath.exist?
      puts "Error: File '#{resolved_filename}' not found in #{iso_dir}" unless silent
      return false
    end

    puts "Verifying #{resolved_filename}..." unless silent
    actual = Digest::SHA256.file(filepath).hexdigest
    expected = checksum.to_s.sub('sha256:', '')

    if actual == expected
      puts "OK Checksum matches: sha256:#{actual[0..15]}..." unless silent
      true
    else
      puts "FAIL Checksum mismatch!" unless silent
      puts "  Expected: sha256:#{expected[0..15]}..." unless silent
      puts "  Got:      sha256:#{actual[0..15]}..." unless silent
      false
    end
  end

  def downloaded?
    iso_path.exist?
  end

  def iso_path
    iso_dir / resolved_filename
  end

  def to_h
    attributes.compact
  end

  private

  def resolved_filename
    filename || "#{id}.iso"
  end

  def iso_dir
    Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'isos'))
  end
end
```

The `iso_dir` could be configurable (from `pim.yml`), but for now a sensible default keeps it simple. If needed later, pass config via a class-level accessor.

### Delete `lib/pim/iso.rb`

The `IsoDownloader` class is fully replaced by model methods. Remove the file.

### Update commands that used `IsoDownloader`:

- `lib/pim/commands/iso/download.rb` — change `downloader.download(iso)` to `iso.download`
- `lib/pim/commands/iso/verify.rb` — change `downloader.verify(iso)` to `iso.verify`
- `lib/pim/build/manager.rb` — change `@downloader.iso_path(iso)` to `iso.iso_path` and `@downloader.downloaded?(iso)` to `iso.downloaded?`
- `lib/pim/verifier.rb` — if it references IsoDownloader, update similarly

### Update `lib/pim.rb` requires:

Remove `require_relative "pim/iso"` (the IsoDownloader file). The model at `lib/pim/models/iso.rb` is already required through `models.rb`.

## Part 2: One class per file, organized into `services/`

Split multi-class files into properly named individual files. Infrastructure and support classes go into `lib/pim/services/`. This keeps `lib/pim/` clean — it should only contain top-level concerns: models, commands, CLI, config, and the services directory.

### `lib/pim/services/` directory:

```
lib/pim/services/
├── architecture_resolver.rb   # Pim::ArchitectureResolver
├── build_config.rb            # Pim::BuildConfig
├── cache_manager.rb           # Pim::CacheManager
├── http.rb                    # Pim::HTTP
├── qemu.rb                    # Pim::Qemu module (constants, helpers)
├── qemu_command_builder.rb    # Pim::QemuCommandBuilder
├── qemu_disk_image.rb         # Pim::QemuDiskImage
├── qemu_vm.rb                 # Pim::QemuVM
├── registry.rb                # Pim::Registry
├── script_loader.rb           # Pim::ScriptLoader
├── ssh_connection.rb          # Pim::SSHConnection
├── system_ssh.rb              # Pim::SystemSSH
├── ventoy_config.rb           # Pim::VentoyConfig
├── ventoy_manager.rb          # Pim::VentoyManager
└── verifier.rb                # Pim::Verifier
```

### Files that move from `lib/pim/` → `lib/pim/services/`:

- `lib/pim/http.rb` → `lib/pim/services/http.rb`
- `lib/pim/qemu.rb` → split into `services/qemu.rb`, `services/qemu_disk_image.rb`, `services/qemu_command_builder.rb`, `services/qemu_vm.rb`
- `lib/pim/ssh.rb` → split into `services/ssh_connection.rb`, `services/system_ssh.rb`
- `lib/pim/ventoy.rb` → split into `services/ventoy_config.rb`, `services/ventoy_manager.rb`
- `lib/pim/build.rb` → split into `services/build_config.rb`, `services/architecture_resolver.rb`, `services/cache_manager.rb`, `services/script_loader.rb`
- `lib/pim/registry.rb` → `lib/pim/services/registry.rb`
- `lib/pim/verifier.rb` → `lib/pim/services/verifier.rb`

Delete the old files after moving.

### Files that stay in `lib/pim/`:

- `lib/pim.rb` — module root
- `lib/pim/config.rb` — project config loader
- `lib/pim/project.rb` — project scaffold/detection
- `lib/pim/models.rb` — FlatRecord setup
- `lib/pim/models/` — FlatRecord models
- `lib/pim/cli.rb` — Dry::CLI registry
- `lib/pim/commands/` — CLI commands
- `lib/pim/build/` — build pipeline (local_builder.rb, manager.rb)
- `lib/pim/templates/` — scaffold templates
- `lib/pim/version.rb` — version constant

## Part 3: Update requires in `lib/pim.rb`

After the split, `lib/pim.rb` should require each file individually:

```ruby
# Services
require_relative "pim/services/http"
require_relative "pim/services/qemu"
require_relative "pim/services/qemu_disk_image"
require_relative "pim/services/qemu_command_builder"
require_relative "pim/services/qemu_vm"
require_relative "pim/services/ssh_connection"
require_relative "pim/services/system_ssh"
require_relative "pim/services/build_config"
require_relative "pim/services/architecture_resolver"
require_relative "pim/services/cache_manager"
require_relative "pim/services/script_loader"
require_relative "pim/services/ventoy_config"
require_relative "pim/services/ventoy_manager"
require_relative "pim/services/registry"
require_relative "pim/services/verifier"

# Project and config
require_relative "pim/project"
require_relative "pim/config"

# Models (via FlatRecord)
require_relative "pim/models"

# Build pipeline
require_relative "pim/build/local_builder"
require_relative "pim/build/manager"

# CLI
require_relative "pim/cli"
```

## Part 4: Verify no circular dependencies

After splitting, check that:
- No file requires a file that requires it back
- Models don't require infrastructure they don't need at load time
- Commands can require what they need without pulling in the world

## File mapping summary

| Old file | Old class(es) | New file(s) | Notes |
|----------|---------------|-------------|-------|
| `lib/pim/iso.rb` | `IsoDownloader` | **deleted** | Methods moved to `Pim::Iso` model |
| `lib/pim/build.rb` | `BuildConfig`, `ArchitectureResolver`, `CacheManager`, `ScriptLoader` | `services/build_config.rb`, `services/architecture_resolver.rb`, `services/cache_manager.rb`, `services/script_loader.rb` | Split into services/ |
| `lib/pim/qemu.rb` | `Qemu`, `QemuDiskImage`, `QemuCommandBuilder`, `QemuVM` | `services/qemu.rb` (module only), `services/qemu_disk_image.rb`, `services/qemu_command_builder.rb`, `services/qemu_vm.rb` | Split into services/ |
| `lib/pim/ssh.rb` | `SSHConnection`, `SystemSSH` | `services/ssh_connection.rb`, `services/system_ssh.rb` | Split into services/ |
| `lib/pim/ventoy.rb` | `VentoyConfig`, `VentoyManager` | `services/ventoy_config.rb`, `services/ventoy_manager.rb` | Split into services/ |
| `lib/pim/http.rb` | `HTTP` | `services/http.rb` | Move to services/ |
| `lib/pim/verifier.rb` | `Verifier` | `services/verifier.rb` | Move to services/ |
| `lib/pim/registry.rb` | `Registry` | `services/registry.rb` | Move to services/ |
| `lib/pim/project.rb` | `Project` | no change | Stays in lib/pim/ |
| `lib/pim/config.rb` | `Config` | no change | Stays in lib/pim/ |
| `lib/pim/models/*.rb` | all models | no change | Stays in lib/pim/models/ |
| `lib/pim/build/*.rb` | `LocalBuilder`, `BuildManager` | no change | Stays in lib/pim/build/ |
| `lib/pim/commands/*.rb` | all commands | no change | Stays in lib/pim/commands/ |

## Test spec

### `spec/pim/models/iso_spec.rb` (additions)

- `iso.iso_path` returns `Pathname` under cache dir
- `iso.iso_path` uses filename attribute when present
- `iso.iso_path` falls back to `"#{id}.iso"` when no filename
- `iso.downloaded?` returns false when file doesn't exist
- `iso.downloaded?` returns true when file exists
- `iso.verify` returns true when checksum matches (mock Digest)
- `iso.verify` returns false when checksum doesn't match
- `iso.download` calls `Pim::HTTP.download` (mock HTTP)
- `iso.download` calls verify after download

### Existing specs — all must still pass

No behavioral changes to other classes, just file locations. All existing specs should pass without modification. If any spec requires a specific file, the require path may need updating.

## Verification

```bash
# All specs pass
bundle exec rspec

# lib/pim/ is clean — only top-level concerns
find lib/pim -name '*.rb' -maxdepth 1 | sort
# Should show: cli.rb, config.rb, models.rb, project.rb, version.rb

# Services directory has all infrastructure
find lib/pim/services -name '*.rb' | sort
# Should show: architecture_resolver.rb, build_config.rb, cache_manager.rb,
#   http.rb, qemu.rb, qemu_command_builder.rb, qemu_disk_image.rb,
#   qemu_vm.rb, registry.rb, script_loader.rb, ssh_connection.rb,
#   system_ssh.rb, ventoy_config.rb, ventoy_manager.rb, verifier.rb

# Old multi-class files are gone
test ! -f lib/pim/iso.rb        # deleted (moved to model)
test ! -f lib/pim/ssh.rb        # moved to services/
test ! -f lib/pim/build.rb      # split into services/
test ! -f lib/pim/qemu.rb       # moved to services/
test ! -f lib/pim/http.rb       # moved to services/
test ! -f lib/pim/ventoy.rb     # split into services/
test ! -f lib/pim/registry.rb   # moved to services/
test ! -f lib/pim/verifier.rb   # moved to services/

# Model methods work
pim c
pim> iso = Iso.find("debian-13-arm64")
pim> iso.iso_path
pim> iso.downloaded?

# Commands still work
pim iso get
pim profile get
pim build get
pim iso download debian-13-arm64  # uses iso.download now
pim iso verify debian-13-arm64    # uses iso.verify now
```
