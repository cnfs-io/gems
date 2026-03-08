---
---

# Plan 03 — Boot Simplification

## Objective

Eliminate `configure_flat_record!` as a separate method. Make `Pim.boot!` apply FlatRecord configuration from the nested config block in `Pim.configure`. Convert `Pim.root` to return Pathname. Remove legacy XDG data_paths from global FlatRecord config.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pim/lib/pim/boot.rb` — current boot sequence
- `~/.local/share/ppm/gems/pim/lib/pim/models.rb` — `configure_flat_record!` (to be removed)
- `~/.local/share/ppm/gems/pim/lib/pim/config.rb` — Config with FlatRecordSettings (from Plan 02)
- `~/.local/share/ppm/gems/flat_record/lib/flat_record/configuration.rb` — FlatRecord.configure API

## Implementation

### 1. `Pim.root` returns Pathname — `lib/pim/boot.rb`

```ruby
def self.root(start_dir = Dir.pwd)
  dir = Pathname(start_dir).expand_path
  loop do
    return dir if (dir / PROJECT_MARKER).exist?
    parent = dir.parent
    return nil if parent == dir
    dir = parent
  end
end

def self.root!(start_dir = Dir.pwd)
  root(start_dir) || raise("No pim.rb found. Run `pim new` to create a project.")
end
```

### 2. Update `data_dir` and `resources_dir` — `lib/pim/boot.rb`

These should return Pathnames:

```ruby
def self.data_dir(project_dir = nil)
  (project_dir || self.project_dir) / "data"
end

def self.resources_dir(project_dir = nil)
  (project_dir || self.project_dir) / "resources"
end

def self.project_dir
  @project_dir ||= root!
end
```

Note: `project_dir` is now a Pathname (set by `root!`). All callers that do string concatenation with these paths will need updating. Pathname's `/` operator handles joining.

### 3. New boot sequence — `lib/pim/boot.rb`

```ruby
def self.boot!(project_dir: nil)
  @project_dir = project_dir ? Pathname(project_dir) : root!
  @config = nil

  # Load pim.rb — this executes Pim.configure and any model-level overrides
  load(@project_dir.join(PROJECT_MARKER).to_s)

  # Apply FlatRecord configuration from the nested config block
  apply_flat_record_config!

  # Reload all models
  reload_models!
end

private_class_method def self.apply_flat_record_config!
  fr_settings = config.flat_record

  FlatRecord.configure do |c|
    c.backend = fr_settings.backend
    c.data_path = data_dir
    c.id_strategy = fr_settings.id_strategy
    c.on_missing_file = fr_settings.on_missing_file
    c.merge_strategy = fr_settings.merge_strategy
    c.read_only = fr_settings.read_only
  end
end

private_class_method def self.reload_models!
  Pim::Iso.reload!
  Pim::Build.reload!
  Pim::Target.reload!
  # Profile is not reloaded here — it may have custom data_paths
  # set in pim.rb that should be preserved
  Pim::Profile.reload!
end
```

### 4. Remove `configure_flat_record!` — `lib/pim/models.rb`

Delete the `configure_flat_record!` method entirely. The file becomes just requires:

```ruby
# frozen_string_literal: true

require "flat_record"

require_relative "models/profile"
require_relative "models/iso"
require_relative "models/build"
require_relative "models/target"
require_relative "models/targets/local"
require_relative "models/targets/proxmox"
require_relative "models/targets/aws"
require_relative "models/targets/iso_target"
```

### 5. Update path usage across codebase

Since `Pim.root`, `Pim.data_dir`, `Pim.resources_dir`, and `Pim.project_dir` now return Pathnames, audit all callers:

- `File.join(Pim.root!, ...)` → `Pim.root!.join(...)`
- `File.join(Pim.data_dir, ...)` → `Pim.data_dir.join(...)`
- `File.exist?(File.join(Pim.root!, ...))` → `Pim.root!.join(...).exist?`

Key files to audit:
- `lib/pim/models/profile.rb` — `find_template` method uses `File.join(Pim.root!, ...)`
- `lib/pim/services/script_loader.rb` — likely uses Pim.root or resources_dir
- `lib/pim/build/local_builder.rb` — uses config.image_dir
- `lib/pim/commands/*.rb` — any command that references project paths
- All spec files that reference Pim.root or project paths

### 6. Data path is now single — just the project's `data/` dir

The old `configure_flat_record!` set:
```ruby
c.data_paths = [
  File.join(Pim::XDG_CONFIG_HOME, "pim"),
  data_dir
]
```

The new `apply_flat_record_config!` sets:
```ruby
c.data_path = data_dir
```

Single path. No XDG. If a model needs additional paths (e.g., Profile reading from a shared location), the user sets `Pim::Profile.data_paths` in `pim.rb`.

## Test Spec

### Update existing specs

Any spec that calls `Pim.root` or `Pim.root!` and expects a String needs to expect a Pathname or call `.to_s`.

Any spec that references `configure_flat_record!` needs updating.

### New specs

```ruby
describe "Pim.root" do
  it "returns a Pathname" do
    # Set up a temp project dir with pim.rb
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "pim.rb"), "Pim.configure { |c| }")
      result = Pim.root(dir)
      expect(result).to be_a(Pathname)
    end
  end
end

describe "Pim.boot!" do
  it "configures FlatRecord from nested config block" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "pim.rb"), <<~RUBY)
        Pim.configure do |config|
          config.flat_record do |fr|
            fr.backend = :yaml
            fr.id_strategy = :string
          end
        end
      RUBY

      Pim.boot!(project_dir: dir)

      expect(FlatRecord.configuration.backend).to eq(:yaml)
      expect(FlatRecord.configuration.id_strategy).to eq(:string)
      expect(FlatRecord.configuration.data_path).to be_a(Pathname)
    end
  end

  it "does not set multi-path by default" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "pim.rb"), "Pim.configure { |c| }")
      Pim.boot!(project_dir: dir)

      expect(FlatRecord.configuration.multi_path?).to be false
    end
  end
end

describe "Pim.data_dir" do
  it "returns a Pathname" do
    expect(Pim.data_dir).to be_a(Pathname)
  end
end
```

## Verification

1. `bundle exec rspec` — all green
2. Grep: no `configure_flat_record!` anywhere in lib/
3. Grep: no `XDG_CONFIG_HOME` in models.rb
4. `Pim.root` returns Pathname in console
5. `Pim.boot!` in a test project configures FlatRecord correctly
