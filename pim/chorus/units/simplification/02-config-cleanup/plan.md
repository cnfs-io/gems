---
---

# Plan 02 — Config Cleanup

## Objective

Remove build-level attributes from `Pim::Config`. Add nested `flat_record` config block to `Pim.configure`. Remove the `BuildConfig` service class.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pim/lib/pim/config.rb` — current Config class
- `~/.local/share/ppm/gems/pim/lib/pim/services/build_config.rb` — BuildConfig (to be removed)
- `~/.local/share/ppm/gems/pim/lib/pim/build/local_builder.rb` — primary consumer of BuildConfig
- `~/.local/share/ppm/gems/pim/lib/pim/build/manager.rb` — creates BuildConfig instances
- `~/.local/share/ppm/gems/pim/spec/` — existing specs
- Search for all references to `BuildConfig`, `config.memory`, `config.cpus`, `config.disk_size`, `config.ssh_user`, `config.ssh_timeout` across the codebase

## Implementation

### 1. Slim down `Pim::Config` — `lib/pim/config.rb`

Remove these attributes from `Config`:
- `memory`
- `cpus`
- `disk_size`
- `ssh_user`
- `ssh_timeout`

Keep these (legitimate global config):
- `iso_dir`
- `image_dir`
- `serve_port`
- `serve_profile`
- `ventoy` (nested block)

Add a `flat_record` nested config holder:

```ruby
class Config
  attr_accessor :iso_dir, :image_dir, :serve_port, :serve_profile

  def initialize
    @iso_dir = File.join(Pim::XDG_CACHE_HOME, "pim", "isos")
    @image_dir = File.join(Pim::XDG_DATA_HOME, "pim", "images")
    @serve_port = 8080
    @serve_profile = nil
    @ventoy = VentoySettings.new
    @flat_record_config = nil
  end

  def ventoy
    yield @ventoy if block_given?
    @ventoy
  end

  def flat_record
    @flat_record_config ||= FlatRecordSettings.new
    yield @flat_record_config if block_given?
    @flat_record_config
  end
end
```

Add `FlatRecordSettings` — a simple struct-like class that holds F/R config values until boot applies them:

```ruby
class FlatRecordSettings
  attr_accessor :backend, :id_strategy, :on_missing_file, :merge_strategy, :read_only

  def initialize
    @backend = :yaml
    @id_strategy = :string
    @on_missing_file = :empty
    @merge_strategy = :replace
    @read_only = false
  end
end
```

### 2. Remove `BuildConfig` — `lib/pim/services/build_config.rb`

Delete this file. Remove the `require_relative` from `lib/pim.rb`.

### 3. Update `LocalBuilder` — `lib/pim/build/local_builder.rb`

`LocalBuilder` currently takes a `config:` parameter (a BuildConfig instance) and reads `config.memory`, `config.cpus`, etc. from it.

Change the constructor to accept a `build:` parameter (a `Pim::Build` instance) instead:

```ruby
def initialize(build:, profile:, profile_name:, arch:, iso_path:, iso_key:)
  @build = build
  @profile = profile
  # ... rest
end
```

Replace all `@config.memory` → `@build.memory`, `@config.cpus` → `@build.cpus`, etc.

For `@config.image_dir` — this stays on `Pim.config`, access it as `Pim.config.image_dir`.

For `@config.ssh_user` and `@config.ssh_timeout` — these move to the build model (plan-04), but for now read from `@build.ssh_user` / `@build.ssh_timeout`. Plan 04 will add those attributes to Build.

**Wait** — this creates a dependency on Plan 04. To avoid that, in this plan:
- Remove `BuildConfig` class
- Update `LocalBuilder` to accept `build:` parameter
- Read `memory`, `cpus`, `disk_size` from `@build` (these already exist on Build model)
- Read `ssh_user`, `ssh_timeout` from `Pim.config` temporarily (they stay on Config until Plan 04 moves them)
- Read `image_dir` from `Pim.config`

This means `ssh_user` and `ssh_timeout` stay on `Pim::Config` in this plan and get removed in Plan 04.

Updated `Config`:
```ruby
attr_accessor :iso_dir, :image_dir, :serve_port, :serve_profile, :ssh_user, :ssh_timeout
```

### 4. Update `BuildManager` — `lib/pim/build/manager.rb`

Find where `BuildConfig.new(build_overrides: ...)` is called. Replace with passing the Build model instance directly to LocalBuilder.

### 5. Remove `build_overrides` pattern from LocalBuilder

The old pattern: `LocalBuilder.new(config: BuildConfig.new(build_overrides: {...}))` with the BuildConfig delegating to Pim.config with overrides.

The new pattern: `LocalBuilder.new(build: build_instance)` where `build_instance` is a `Pim::Build` record that already has `memory`, `cpus`, `disk_size` as attributes (with defaults from the Build model).

Remove the `build_overrides` parameter, the `@build_overrides` instance variable, and all `@build_overrides[:x] || @config.x` patterns.

## Test Spec

### Update existing specs

- Any spec referencing `BuildConfig` needs updating
- Any spec setting `config.memory`, `config.cpus`, `config.disk_size` needs updating
- Config spec should verify the new slim attribute set

### New specs

```ruby
describe Pim::Config do
  it "has iso_dir with XDG default" do
    config = Pim::Config.new
    expect(config.iso_dir).to include("pim/isos")
  end

  it "has image_dir with XDG default" do
    config = Pim::Config.new
    expect(config.image_dir).to include("pim/images")
  end

  it "does not respond to memory" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:memory)
  end

  it "does not respond to cpus" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:cpus)
  end

  it "does not respond to disk_size" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:disk_size)
  end

  describe "flat_record nested config" do
    it "yields a FlatRecordSettings object" do
      config = Pim::Config.new
      config.flat_record do |fr|
        expect(fr).to be_a(Pim::FlatRecordSettings)
        fr.backend = :json
      end
      expect(config.flat_record.backend).to eq(:json)
    end

    it "has sensible defaults" do
      config = Pim::Config.new
      expect(config.flat_record.backend).to eq(:yaml)
      expect(config.flat_record.id_strategy).to eq(:string)
    end
  end
end
```

## Verification

1. `bundle exec rspec` — all green
2. Grep: no references to `BuildConfig` remain (except possibly in this plan doc)
3. Grep: `Pim::Config` does not have `attr_accessor :memory` or `:cpus` or `:disk_size`
4. `Pim.configure { |c| c.flat_record { |fr| fr.backend = :yaml } }` works in console
