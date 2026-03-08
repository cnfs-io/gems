---
---

# Plan 05 — Template and Profile Cleanup

## Objective

Update the `pim new` scaffold template to generate the new slim `pim.rb`. Remove the `SHARED_PROFILES_DIR` constant from Profile. Clean up any remaining XDG references in model code. Update all specs to reflect the new conventions.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pim/lib/pim/new/scaffold.rb` — scaffold logic
- `~/.local/share/ppm/gems/pim/lib/pim/new/template/pim.rb` — current pim.rb template
- `~/.local/share/ppm/gems/pim/lib/pim/models/profile.rb` — has SHARED_PROFILES_DIR constant
- `~/.local/share/ppm/gems/pim/spec/` — all specs

## Implementation

### 1. Update pim.rb template — `lib/pim/new/template/pim.rb`

Replace the entire template with the new slim version:

```ruby
# PIM Project Configuration
#
# This file is loaded when PIM boots. It configures PIM and its dependencies.
# Everything below the configure block is regular Ruby — set per-model
# overrides, require additional files, etc.

Pim.configure do |config|
  # Where ISOs are cached (default: ~/.cache/pim/isos)
  # config.iso_dir = "~/.cache/pim/isos"

  # Where built images are stored (default: ~/.local/share/pim/images)
  # config.image_dir = "~/.local/share/pim/images"

  # Preseed server defaults
  # config.serve_port = 8080

  # FlatRecord configuration
  config.flat_record do |fr|
    fr.backend = :yaml
    fr.id_strategy = :string
  end

  # Ventoy USB management
  # config.ventoy do |v|
  #   v.version = "1.0.99"
  #   v.device = "/dev/sdX"
  # end
end

# Per-model data path overrides (optional)
#
# By default, all models read from <project>/data/<source>/
# To share data with other tools (e.g., PCS), set a model's data_paths:
#
# Pim::Profile.data_paths = [Pim.root.join("../share/profiles")]
#
# To merge shared + project-local data (shared first, project overrides):
#
# Pim::Profile.data_paths = [
#   Pim.root.join("../share/profiles"),
#   Pim.root.join("data/profiles")
# ]
```

### 2. Remove SHARED_PROFILES_DIR from Profile — `lib/pim/models/profile.rb`

Delete the constant:
```ruby
# DELETE THIS:
SHARED_PROFILES_DIR = File.join(
  ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")),
  "provisioning"
)
```

Also remove any `FileUtils.mkdir_p(Pim::Profile::SHARED_PROFILES_DIR)` calls that may exist elsewhere (check models.rb — already removed in Plan 03, but verify).

### 3. Audit Profile for XDG remnants — `lib/pim/models/profile.rb`

The `find_template` method uses `Pim.root!` — this now returns Pathname (from Plan 03). Update to use Pathname methods:

```ruby
def find_template(subdir, filename)
  path = Pim.root!.join(subdir, filename)
  return path.to_s if path.exist?
  nil
end
```

### 4. Audit all XDG references

Search the entire `lib/pim/` directory for:
- `XDG_CONFIG_HOME` — should only appear in the XDG constant definitions in `lib/pim.rb` and in `Config` defaults for `iso_dir`/`image_dir`
- `XDG_DATA_HOME` — same
- `XDG_CACHE_HOME` — same
- `~/.config/pim` — should not appear anywhere
- `~/.local/share/provisioning` — should not appear anywhere
- `SHARED_PROFILES_DIR` — should not appear anywhere

### 5. Update scaffold spec

If there's a spec for `Pim::New::Scaffold`, update it to verify the new template content. The spec should check that a generated project has a `pim.rb` that contains `config.flat_record`.

### 6. Comprehensive spec audit

Run the full suite and fix any failures caused by:
- `Pim.root` returning Pathname instead of String
- Missing `configure_flat_record!`
- Missing `BuildConfig`
- Missing `Config#memory` / `Config#ssh_user` etc.
- Missing `Profile::SHARED_PROFILES_DIR`

This plan is the cleanup sweep — catch anything the previous plans missed.

## Test Spec

### Scaffold spec

```ruby
describe Pim::New::Scaffold do
  it "generates pim.rb with flat_record config block" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "test-project")
      Pim::New::Scaffold.new(target).create

      content = File.read(File.join(target, "pim.rb"))
      expect(content).to include("config.flat_record")
      expect(content).to include("fr.backend = :yaml")
      expect(content).to include("fr.id_strategy = :string")
    end
  end

  it "generates pim.rb with data_paths documentation" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "test-project")
      Pim::New::Scaffold.new(target).create

      content = File.read(File.join(target, "pim.rb"))
      expect(content).to include("Pim::Profile.data_paths")
      expect(content).to include("../share/profiles")
    end
  end
end
```

### Integration spec — full boot cycle

```ruby
describe "full boot cycle" do
  it "boots cleanly from a new project scaffold" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "test-project")
      Pim::New::Scaffold.new(target).create
      Pim.boot!(project_dir: target)

      expect(Pim.root).to be_a(Pathname)
      expect(Pim.root.join("pim.rb")).to be_file
      expect(FlatRecord.configuration.backend).to eq(:yaml)
      expect(FlatRecord.configuration.data_path).to be_a(Pathname)
      expect(FlatRecord.configuration.data_path.to_s).to end_with("data")
    end
  end
end
```

## Verification

1. `cd ~/.local/share/ppm/gems/pim && bundle exec rspec` — all green
2. `cd ~/.local/share/ppm/gems/flat_record && bundle exec rspec` — all green
3. Grep: no `SHARED_PROFILES_DIR` in lib/
4. Grep: no `configure_flat_record!` in lib/
5. Grep: no `BuildConfig` in lib/
6. Grep: no `config.memory` or `config.cpus` or `config.disk_size` in lib/
7. Grep: no `config.ssh_user` or `config.ssh_timeout` in lib/
8. Grep: no `~/.config/pim` in lib/
9. Grep: no `~/.local/share/provisioning` in lib/
10. `pim new /tmp/test-simplification` creates a clean project with the new template
11. `cd /tmp/test-simplification && pim console` boots successfully
