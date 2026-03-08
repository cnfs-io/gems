---
---

# Plan 05: Ventoy Self-Managed Download

## Context

Read these files before starting:

- `lib/pim/ventoy.rb` — `PimVentoy::Config` and `PimVentoy::Manager` (will be `Pim::VentoyConfig` and `Pim::VentoyManager` after plan-04)
- `lib/pim/commands/ventoy/prepare.rb` — calls `manager.verify_ventoy_install`
- `lib/pim/commands/ventoy/copy.rb` — uses ventoy mount point
- `lib/pim/commands/ventoy/status.rb` — checks ventoy install
- `lib/pim/iso.rb` — `IsoManager#download_file` for reference on HTTP download with redirects and progress
- `lib/pim/templates/project/pim.yml` — default ventoy config section

**Note:** This plan assumes plan-04 is complete. All classes are under `Pim::` namespace. References below use post-plan-04 names.

## Objective

Make the PIM gem self-sufficient for Ventoy — no external package manager or install script needed. Any command that requires Ventoy (`prepare`, `copy`, `status`) automatically downloads and verifies Ventoy binaries if they're not already cached.

## Design decisions

### Auto-download with `ensure_ventoy!`

Every ventoy command calls `Pim::VentoyManager#ensure_ventoy!` before doing anything. This method:

1. Checks if `Ventoy2Disk.sh` exists in the expected cache location
2. If present, returns immediately (idempotent)
3. If absent, downloads the tarball, verifies checksum, extracts, cleans up tarball

No separate `pim ventoy install` command needed. The first time you use any ventoy command, it just works.

### Config additions

The ventoy section of `pim.yml` needs a `url` field. Currently the SourceForge URL was hardcoded in the bash install script. Move it to config:

```yaml
ventoy:
  version: v1.0.99
  dir: ventoy-1.0.99
  file: ventoy-1.0.99-linux.tar.gz
  url: https://sourceforge.net/projects/ventoy/files/v1.0.99/ventoy-1.0.99-linux.tar.gz/download
  checksum: sha256:467cdd188a7f739bc706adbc1d695f61ffdefc95916adb015947d80829f00a3d
```

The scaffold template (`lib/pim/templates/project/pim.yml`) should include this full ventoy section as a commented-out example or with reasonable defaults.

### Cache location

```
~/.cache/pim/ventoy/
├── ventoy-1.0.99-linux.tar.gz    # temporary — deleted after extraction
├── ventoy-1.0.99/                # extracted binaries
│   ├── Ventoy2Disk.sh
│   └── ...
└── mnt/                          # mount point for USB operations
```

This uses `Pim::XDG_CACHE_HOME` (defined in plan-04) rather than hardcoded paths.

### Reuse download infrastructure

`Pim::IsoManager` has a `download_file` method with redirect following (up to 5 hops) and progress reporting. Rather than duplicating this, extract it to a shared utility module:

```ruby
module Pim
  module HTTP
    # Download a file with redirect following and progress reporting
    def self.download(url, destination, redirect_limit: 5)
      # ... extracted from IsoManager#download_file
    end
  end
end
```

Both `IsoManager` and `VentoyManager` use `Pim::HTTP.download`. This goes in a new file `lib/pim/http.rb`.

### Checksum verification

Same pattern as ISO verification — SHA256 of the downloaded tarball compared against the config value. Extract the checksum utility too if it isn't already shared:

```ruby
module Pim
  module HTTP
    def self.verify_checksum(filepath, expected_checksum)
      expected = expected_checksum.to_s.sub(/^sha256:/, '')
      actual = Digest::SHA256.file(filepath).hexdigest
      actual == expected
    end
  end
end
```

### Extraction

After download and verification, extract the tarball:

```ruby
def extract_tarball(tarball_path, destination)
  FileUtils.mkdir_p(destination)
  stdout, stderr, status = Open3.capture3(
    'tar', '-xzf', tarball_path, '-C', destination
  )
  raise "Extraction failed: #{stderr}" unless status.success?
end
```

Then delete the tarball to save disk space.

## Implementation

### 1. Create `lib/pim/http.rb`

Extract `download_file` from `Pim::IsoManager` into `Pim::HTTP.download`. Also add `Pim::HTTP.verify_checksum`. Keep the progress reporting (prints download progress to stdout).

### 2. Update `Pim::IsoManager`

Replace the private `download_file` and `calculate_checksum` methods with calls to `Pim::HTTP.download` and `Pim::HTTP.verify_checksum`. Verify ISO download and verify commands still work.

### 3. Add `url` to ventoy config

Update `Pim::VentoyConfig` to expose a `url` accessor:

```ruby
def url
  @ventoy_section['url']
end
```

### 4. Update scaffold template

In `lib/pim/templates/project/pim.yml`, add the full ventoy section with `url` field. This can be commented out by default since ventoy is Linux-only and not all projects need it.

### 5. Implement `ensure_ventoy!` on `Pim::VentoyManager`

```ruby
def ensure_ventoy!
  ventoy_script = @config.ventoy_dir / 'Ventoy2Disk.sh'
  return true if ventoy_script.exist?

  unless @config.url && @config.checksum
    Pim.exit!(1, message: "Ventoy URL and checksum must be configured in pim.yml")
  end

  cache_dir = Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'ventoy'))
  FileUtils.mkdir_p(cache_dir)

  tarball_path = cache_dir / @config.file

  # Download
  puts "Downloading Ventoy #{@config.version}..."
  Pim::HTTP.download(@config.url, tarball_path.to_s)

  # Verify
  puts "Verifying checksum..."
  unless Pim::HTTP.verify_checksum(tarball_path.to_s, @config.checksum)
    tarball_path.delete if tarball_path.exist?
    Pim.exit!(1, message: "Checksum verification failed for #{@config.file}")
  end
  puts "OK Checksum verified"

  # Extract
  puts "Extracting..."
  extract_tarball(tarball_path.to_s, cache_dir.to_s)

  # Clean up tarball
  tarball_path.delete if tarball_path.exist?

  # Create mount point
  FileUtils.mkdir_p(@config.mount_point)

  # Verify extraction succeeded
  unless ventoy_script.exist?
    Pim.exit!(1, message: "Extraction completed but Ventoy2Disk.sh not found at expected location")
  end

  puts "OK Ventoy #{@config.version} ready"
  true
end
```

### 6. Update `verify_ventoy_install` 

Replace the current method that just checks and prints an error with a call to `ensure_ventoy!`:

```ruby
def verify_ventoy_install
  ensure_ventoy!
end
```

Or remove `verify_ventoy_install` entirely and have commands call `ensure_ventoy!` directly.

### 7. Update ventoy commands

In `prepare.rb`, `copy.rb`, and `status.rb` — replace the `verify_ventoy_install` check with `ensure_ventoy!`. For `status.rb`, it might make sense to just check without downloading (informational only). Add a `--no-download` flag or have status report "not installed" rather than triggering a download.

### 8. Add `pim ventoy download` command (optional)

For users who want to explicitly pre-download Ventoy without running a ventoy operation:

```ruby
# lib/pim/commands/ventoy/download.rb
class Download < Dry::CLI::Command
  desc "Download and verify Ventoy binaries"

  def call(**)
    manager = Pim::VentoyManager.new(config: Pim::Config.new.ventoy)
    manager.ensure_ventoy!
  end
end
```

Register as `register "ventoy download", Commands::Ventoy::Download`.

## Test spec

### `spec/pim/http_spec.rb` (new)

Test `Pim::HTTP`:

- `.verify_checksum` returns true for matching checksum
- `.verify_checksum` returns false for mismatching checksum
- `.verify_checksum` strips `sha256:` prefix from expected value
- `.download` is tested with a mock HTTP server or stubbed `Net::HTTP` (don't hit real URLs in specs)
- `.download` follows redirects up to limit
- `.download` raises on HTTP errors

### `spec/pim/ventoy_manager_spec.rb` (new or update)

Test `Pim::VentoyManager#ensure_ventoy!`:

- Returns immediately if `Ventoy2Disk.sh` already exists (idempotent)
- Exits with error if URL not configured
- Exits with error if checksum not configured
- Downloads tarball when not cached (stub `Pim::HTTP.download`)
- Verifies checksum after download
- Exits with error and deletes tarball if checksum fails
- Extracts tarball after verification
- Deletes tarball after extraction
- Creates mount point directory

### `spec/pim/ventoy_config_spec.rb` (update)

- Exposes `url` accessor
- Returns nil when url not in config

### `spec/pim/iso_manager_spec.rb` (update)

- Verify `IsoManager` now uses `Pim::HTTP.download` instead of private method
- Download and verify behavior unchanged

## Verification

```bash
# All specs pass
bundle exec rspec

# Shared HTTP module exists
grep -rn "Pim::HTTP" lib/pim/http.rb    # should show module definition
grep -rn "Pim::HTTP" lib/pim/iso.rb     # should show usage
grep -rn "Pim::HTTP" lib/pim/ventoy.rb  # should show usage

# No private download_file in IsoManager
grep -n "def download_file" lib/pim/iso.rb  # should return nothing

# Ventoy auto-download works (manual, Linux only)
cd /path/to/project
# Ensure ventoy cache is empty:
rm -rf ~/.cache/pim/ventoy/
pim ventoy status    # should download ventoy automatically, then show status
ls ~/.cache/pim/ventoy/  # should show extracted directory and mnt/

# Idempotent — second run skips download
pim ventoy status    # should not re-download

# Config has url field
pim config get ventoy.url  # should return the SourceForge URL
```
