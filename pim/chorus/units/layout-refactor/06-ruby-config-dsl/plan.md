---
---

# Plan 06 — Ruby Config DSL

## Context

Read before starting:
- `lib/pim/boot.rb` — created in plan-05, has `boot!` which loads `pim.rb`
- `lib/pim.rb` — current `Pim::Config` class (YAML-based)
- `lib/pim/services/build_config.rb` — `BuildConfig` with defaults and accessors
- `lib/pim/services/ventoy_config.rb` — `VentoyConfig`
- `lib/pim/new/template/pim.yml` — current YAML template (to be replaced with `pim.rb`)

## Goal

Replace the YAML-based `Pim::Config` with a Ruby DSL. The project marker becomes `pim.rb` which executes a `Pim.configure` block. Eliminate `.env` file — Ruby handles ENV lookups directly.

## What Goes in Config

Project-level infrastructure settings only. NOT per-build parameters.

| Setting | Description | Default |
|---------|-------------|---------|
| `iso_dir` | Where ISOs are cached | `~/.cache/pim/isos` |
| `image_dir` | Where built qcow2s are stored | `~/.local/share/pim/images` |
| `serve_port` | Default preseed server port | `8080` |
| `serve_profile` | Default profile for `pim serve` | `nil` |
| `ssh_user` | Default SSH user for provisioning | `"ansible"` |
| `ssh_timeout` | SSH wait timeout in seconds | `1800` |
| `disk_size` | Default disk size for new images | `"20G"` |
| `memory` | Default memory in MB | `2048` |
| `cpus` | Default CPU count | `2` |
| `ventoy` | Ventoy settings (nested) | `{}` |

Note: `disk_size`, `memory`, `cpus`, `ssh_user` are *defaults* — per-build recipes in `data/builds/*.yml` can override them. The config just sets the baseline.

## Implementation

### 1. Create `lib/pim/config.rb` (rewrite)

Replace the YAML-loading Config with a Ruby DSL object:

```ruby
# frozen_string_literal: true

module Pim
  class Config
    attr_accessor :iso_dir, :image_dir,
                  :serve_port, :serve_profile,
                  :ssh_user, :ssh_timeout,
                  :disk_size, :memory, :cpus

    attr_reader :ventoy

    def initialize
      # Defaults
      @iso_dir = File.join(Pim::XDG_CACHE_HOME, "pim", "isos")
      @image_dir = File.join(Pim::XDG_DATA_HOME, "pim", "images")
      @serve_port = 8080
      @serve_profile = nil
      @ssh_user = "ansible"
      @ssh_timeout = 1800
      @disk_size = "20G"
      @memory = 2048
      @cpus = 2
      @ventoy = VentoySettings.new
    end

    def ventoy
      yield @ventoy if block_given?
      @ventoy
    end
  end

  class VentoySettings
    attr_accessor :version, :dir, :file, :url, :checksum, :device

    def initialize
      @version = nil
      @dir = nil
      @file = nil
      @url = nil
      @checksum = nil
      @device = nil
    end
  end

  def self.configure
    @config ||= Config.new
    yield @config if block_given?
    @config
  end

  def self.config
    @config || configure
  end
end
```

### 2. Update `boot.rb` to wire config into boot

```ruby
def self.boot!(project_dir: nil)
  @project_dir = project_dir || root!
  @config = nil  # reset config before loading pim.rb
  load File.join(@project_dir, PROJECT_MARKER)
  configure_flat_record!(project_dir: @project_dir)
end

def self.reset!
  @project_dir = nil
  @config = nil
end
```

### 3. Rewrite `BuildConfig` to delegate to `Pim.config`

`BuildConfig` currently parses a YAML hash and provides accessors. Rewrite it to read from `Pim.config` with per-build overrides:

```ruby
# frozen_string_literal: true

module Pim
  class BuildConfig
    def initialize(build_overrides: {})
      @overrides = build_overrides
    end

    def image_dir
      Pathname.new(File.expand_path(Pim.config.image_dir))
    end

    def disk_size
      @overrides[:disk_size] || Pim.config.disk_size
    end

    def memory
      @overrides[:memory] || Pim.config.memory
    end

    def cpus
      @overrides[:cpus] || Pim.config.cpus
    end

    def ssh_user
      @overrides[:ssh_user] || Pim.config.ssh_user
    end

    def ssh_timeout
      @overrides[:ssh_timeout] || Pim.config.ssh_timeout
    end
  end
end
```

Note: `BuildConfig` no longer takes `runtime_config:` or `project_dir:` — it reads from the global `Pim.config` which is populated by `pim.rb` during boot.

### 4. Rewrite `VentoyConfig` to delegate to `Pim.config.ventoy`

```ruby
# frozen_string_literal: true

module Pim
  class VentoyConfig
    def version
      Pim.config.ventoy.version
    end

    def dir
      Pim.config.ventoy.dir
    end

    def file
      Pim.config.ventoy.file
    end

    def url
      Pim.config.ventoy.url
    end

    def checksum
      Pim.config.ventoy.checksum
    end

    def device
      Pim.config.ventoy.device
    end

    def ventoy_dir
      Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'ventoy', dir.to_s))
    end

    def mount_point
      Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'ventoy', 'mnt'))
    end

    def iso_dir
      Pathname.new(Pim.config.iso_dir)
    end
  end
end
```

### 5. Update `Pim::Config` usage in `lib/pim.rb`

The old `Pim::Config` class was instantiated as `Pim::Config.new(project_dir: dir)` by various callers. These need to change:

- **`Pim::Config.new`** calls → Replace with `Pim.config` (the module-level accessor)
- **`config.build`** → `Pim::BuildConfig.new` or direct `Pim.config` access
- **`config.ventoy`** → `Pim::VentoyConfig.new` or direct `Pim.config.ventoy` access
- **`config.serve_defaults`** → `Pim.config.serve_port`, `Pim.config.serve_profile`
- **`config.profile(name)`** and **`config.profile_names`** → These are FlatRecord delegations, move them to `Pim` module methods or keep them as convenience methods

Search for all `Pim::Config.new` in the codebase and update callers.

### 6. Update Server to use Pim.config

The Server currently receives a `port:` parameter. Callers that default from config should use `Pim.config.serve_port`. No change to Server itself — just its callers (e.g., `Commands::Serve`).

### 7. Update the scaffold template

Delete `lib/pim/new/template/pim.yml` (if still present after plan-05) and `lib/pim/new/template/.env` (if present).

Create `lib/pim/new/template/pim.rb`:

```ruby
# PIM Project Configuration
#
# This file is loaded when PIM boots. Use it to override defaults.
# All settings below show their default values.

Pim.configure do |config|
  # Where ISOs are cached
  # config.iso_dir = "~/.cache/pim/isos"

  # Where built images are stored
  # config.image_dir = "~/.local/share/pim/images"

  # Preseed server defaults
  # config.serve_port = 8080
  # config.serve_profile = nil

  # Build defaults (can be overridden per-build in data/builds/)
  # config.disk_size = "20G"
  # config.memory = 2048
  # config.cpus = 2

  # SSH provisioning defaults
  # config.ssh_user = "ansible"
  # config.ssh_timeout = 1800

  # Ventoy USB management
  # config.ventoy do |v|
  #   v.version = "1.0.99"
  #   v.device = "/dev/sdX"
  # end
end
```

### 8. Update `Pim::New::Scaffold::SCAFFOLD_DIRS`

Remove `.env` from scaffold if it was included. The only top-level file is now `pim.rb`.

## Test Spec

### `spec/pim/config_spec.rb` (rewrite)

```ruby
RSpec.describe Pim::Config do
  before { Pim.reset! }

  it "provides sensible defaults" do
    config = Pim.configure
    expect(config.memory).to eq(2048)
    expect(config.cpus).to eq(2)
    expect(config.disk_size).to eq("20G")
    expect(config.ssh_user).to eq("ansible")
    expect(config.ssh_timeout).to eq(1800)
    expect(config.serve_port).to eq(8080)
  end

  it "accepts overrides via configure block" do
    Pim.configure do |c|
      c.memory = 4096
      c.serve_port = 9090
    end
    expect(Pim.config.memory).to eq(4096)
    expect(Pim.config.serve_port).to eq(9090)
  end

  it "supports ventoy nested config" do
    Pim.configure do |c|
      c.ventoy do |v|
        v.version = "1.0.99"
        v.device = "/dev/sdb"
      end
    end
    expect(Pim.config.ventoy.version).to eq("1.0.99")
    expect(Pim.config.ventoy.device).to eq("/dev/sdb")
  end

  it "allows ENV in config values" do
    Pim.configure do |c|
      c.iso_dir = ENV.fetch("PIM_ISO_DIR", "/custom/isos")
    end
    expect(Pim.config.iso_dir).to eq("/custom/isos")
  end
end
```

### `spec/pim/build_config_spec.rb`

Test that BuildConfig reads from Pim.config and allows overrides.

### Update `spec/pim/new/scaffold_spec.rb`

- Check for `pim.rb` (not `pim.yml`) in scaffold output
- Remove `.env` check
- Config integration test loads `pim.rb` via `Pim.boot!`

### Update all specs that create temp project dirs

Any spec that creates a `pim.yml` as the project marker must create `pim.rb` instead. Minimal content:

```ruby
File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
```

## Verification

```bash
bundle exec rspec
# All pass

# Manual
pim new /tmp/testruby
cat /tmp/testruby/pim.rb     # Ruby config with commented defaults
ls /tmp/testruby/.env         # should NOT exist
cd /tmp/testruby
pim profile list              # boots via pim.rb, loads FlatRecord
pim config list               # shows config values from Pim.config
```
