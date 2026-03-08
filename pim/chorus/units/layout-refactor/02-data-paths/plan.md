---
---

# Plan 02 — Data Paths

## Context

Read before starting:
- `lib/pim/models.rb` — `configure_flat_record!` with data_paths setup
- `lib/pim/models/profile.rb` — `source "profiles"`, custom data_paths, SHARED_PROFILES_DIR
- `lib/pim/models/iso.rb` — `source "isos"`
- `lib/pim/models/build.rb` — `source "builds"`
- `lib/pim/models/target.rb` — `source "targets"`
- `docs/layout-refactor/README.md` — target layout

## Goal

Update FlatRecord data_paths so models resolve YAML files from `data/` subdirectories instead of project root.

## How FlatRecord Source Resolution Works

When a model declares `source "builds"`, FlatRecord looks for:
- `<data_path>/builds.yml` — single-file source
- `<data_path>/builds/*.yml` — directory source (globs all YAML files)

Currently `data_paths` includes the project root, so `source "builds"` finds `<project>/builds.yml`.

With the new layout, `data/builds/default.yml` means we need `data_paths` to include `<project>/data` so FlatRecord resolves `<project>/data/builds/default.yml` via the directory glob pattern.

## Implementation

### 1. Update `Pim.configure_flat_record!` in `lib/pim/models.rb`

Change the data_paths from project root to `data/` subdirectory:

```ruby
def self.configure_flat_record!(project_dir: nil)
  project_dir ||= Pim::Project.root!
  data_dir = File.join(project_dir, "data")

  FlatRecord.configure do |c|
    c.backend = :yaml
    c.data_paths = [
      File.join(Pim::XDG_CONFIG_HOME, "pim"),
      data_dir
    ]
    c.merge_strategy = :deep_merge
    c.id_strategy = :string
  end

  # Profile reads from shared provisioning path + project data dir
  FileUtils.mkdir_p(Pim::Profile::SHARED_PROFILES_DIR)
  Pim::Profile.data_paths = [Pim::Profile::SHARED_PROFILES_DIR, data_dir]

  Pim::Iso.reload!
  Pim::Build.reload!
  Pim::Target.reload!
end
```

### 2. Add `DATA_DIR` constant to `Pim::Project`

Add a constant for the data directory path relative to project root:

```ruby
DATA_DIR = "data"
BUILDERS_DIR = "builders"
```

And a helper method:

```ruby
def self.data_dir(project_dir = nil)
  File.join((project_dir || root!), DATA_DIR)
end

def self.builders_dir(project_dir = nil)
  File.join((project_dir || root!), BUILDERS_DIR)
end
```

### 3. Verify model source names are unchanged

The model `source` declarations stay the same:
- `Profile` → `source "profiles"` → resolves to `data/profiles/*.yml` ✓
- `Iso` → `source "isos"` → resolves to `data/isos/*.yml` ✓
- `Build` → `source "builds"` → resolves to `data/builds/*.yml` ✓
- `Target` → `source "targets"` → resolves to `data/targets/*.yml` ✓

No changes needed in model files.

### 4. Update XDG config path handling

The XDG config path (`~/.config/pim`) is used as a secondary data_path for global defaults. If users have YAML files there, they follow the old flat pattern (`~/.config/pim/profiles.yml`). This should still work since FlatRecord checks both single-file and directory sources. **No change needed** — but verify this in tests.

## Test Spec

### Unit tests in `spec/pim/models/`

For each model spec that sets up test data, update fixture paths:

- Where tests create `profiles.yml` in a temp dir → create `data/profiles/default.yml` instead
- Same for `builds.yml` → `data/builds/default.yml`
- Same for `isos.yml` → `data/isos/default.yml`
- Same for `targets.yml` → `data/targets/default.yml`

### Update `spec/pim/project_spec.rb`

Un-pend the config integration test from plan-01. It should now pass:

```ruby
it "scaffold files produce valid config" do
  config = Pim::Config.new(project_dir: target)
  expect(config.profile_names).to include("default")
  expect(config.profile("default")).to include("hostname")
end
```

### Add data_dir resolution test

```ruby
describe "Pim::Project.data_dir" do
  it "returns data/ under project root" do
    expect(Pim::Project.data_dir(target)).to eq(File.join(target, "data"))
  end
end
```

## Verification

```bash
bundle exec rspec spec/pim/models/ spec/pim/project_spec.rb spec/pim/config_spec.rb
# All pass

# Manual: from a scaffolded project
pim new /tmp/testproject
cd /tmp/testproject
pim profile list    # should show 'default'
pim iso list        # should show empty
pim build list      # should show empty
pim target list     # should show 'local'
```
