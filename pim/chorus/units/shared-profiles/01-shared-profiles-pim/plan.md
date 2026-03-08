---
---

# Plan 01 — Shared Profiles (PIM side)

## Objective

Reconfigure PIM's Profile model to read from the shared XDG location `~/.local/share/provisioning/profiles.yml` as the primary data source, with the project's local `profiles.yml` as an optional override layer using FlatRecord multi-path loading.

## Context

Read before starting:
- `lib/pim/models/profile.rb` — current Profile model
- `lib/pim.rb` — main module, `configure_flat_record!` method
- `lib/pim/flat_record_config.rb` — if it exists, FlatRecord configuration
- `lib/pim/project.rb` — project root detection
- FlatRecord multi-path: `~/.local/share/ppm/gems/flat_record/lib/flat_record/configuration.rb` — `data_paths`, `multi_path?`
- FlatRecord store: `~/.local/share/ppm/gems/flat_record/lib/flat_record/store.rb` — multi-path loading logic

## Design

### The problem with global multi-path

FlatRecord's `data_paths` configuration is global — it applies to all models. But for PIM, only `Profile` should read from the shared location. ISOs, builds, and targets should continue reading from the project directory only.

Two approaches:

**Option A — Per-model data path override.** Add the ability for a model to specify its own data path(s), independent of the global configuration. This would be a FlatRecord enhancement.

**Option B — Configure profiles separately.** Use FlatRecord's existing `source` class method to point at an absolute path. But `source` only controls the filename, not the directory.

**Option C — Use a separate FlatRecord configuration for profiles.** FlatRecord doesn't support per-model configs today.

The cleanest solution is **Option A** — a per-model data path. This is a small FlatRecord enhancement that's useful beyond this use case. The Profile model would declare:

```ruby
class Profile < FlatRecord::Base
  data_paths ["~/.local/share/provisioning", "./data"]
  read_only true
  merge_strategy :deep_merge
  # ...
end
```

The first path is the shared location (read-only, provides defaults), the second is the project directory (provides overrides). FlatRecord's existing multi-path merge logic handles the rest.

### FlatRecord enhancement needed

Add a `data_paths` class method to `FlatRecord::Base` that overrides the global `FlatRecord.configuration.data_paths` for that specific model. The Store already supports multi-path loading — it just needs to check for a model-level override before falling back to the global config.

This is a prerequisite change in flat_record. Create a plan in flat_record's extensions tier for this.

### PIM changes (after flat_record enhancement)

#### `lib/pim/models/profile.rb`

```ruby
# frozen_string_literal: true

require "set"

module Pim
  class Profile < FlatRecord::Base
    SHARED_PROFILES_DIR = File.join(
      ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")),
      "provisioning"
    )

    data_paths [SHARED_PROFILES_DIR]  # project path appended at boot
    source "profiles"
    read_only true
    merge_strategy :deep_merge

    # ... all existing attributes and methods unchanged
  end
end
```

#### Boot configuration

During `Pim.configure_flat_record!`, after resolving the project root, append the project data path to Profile's data_paths:

```ruby
def self.configure_flat_record!
  project_data = File.join(Project.root!, "data") if Project.root

  FlatRecord.configure do |c|
    c.data_path = project_data || "./data"
  end

  # Profile reads from shared location + project (if it exists)
  if project_data
    Pim::Profile.data_paths = [Pim::Profile::SHARED_PROFILES_DIR, project_data]
  end
end
```

#### Ensure shared directory exists

On first run (or in `pim new`), create `~/.local/share/provisioning/` if it doesn't exist. If a project has profiles that should be shared, provide a migration helper:

```bash
# One-time migration (manual or via a pim command)
mkdir -p ~/.local/share/provisioning
cp my-project/data/profiles.yml ~/.local/share/provisioning/profiles.yml
```

Optionally, add a `pim profile export` command that copies project profiles to the shared location. But this is a nice-to-have — manual copy works fine for now.

### PCS-specific attributes

Add PCS-specific attributes to PIM's Profile model so they're preserved in the shared YAML:

```ruby
# PCS-specific (PIM ignores these but preserves them in the file)
attribute :interface, :string
attribute :device, :string
```

Actually — since PIM's Profile model is read-only, it doesn't write to the shared file. So PCS-specific attributes will be loaded into PIM's model objects but never displayed unless the view includes them. This is fine. PIM's ProfilesView only shows the columns it declares.

However, if PIM doesn't declare the PCS attributes, FlatRecord/ActiveModel will silently ignore them when loading. They won't be lost from the YAML because PIM never writes to the file (read-only). So we don't actually need to declare PCS attributes in PIM's model — they're preserved by virtue of PIM never writing.

**Decision: PIM's Profile model does NOT need to declare PCS-specific attributes.** The shared YAML file contains the union of all attributes. Each tool's model only declares what it needs. Read-only mode ensures no data loss.

## Implementation Order

1. **flat_record enhancement** — Add per-model `data_paths` class method (separate plan in flat_record)
2. **Update PIM Profile model** — Add `SHARED_PROFILES_DIR` constant, configure `data_paths`
3. **Update boot** — Append project data path to Profile's data_paths during configure
4. **Update `pim new`** — Ensure `~/.local/share/provisioning/` exists, don't create `profiles.yml` in project data dir (or create it as optional override)
5. **Test** — Verify shared profiles are loaded, project overrides merge correctly
6. **Migration docs** — Document how to move existing project profiles to shared location

## Prerequisites

**flat_record extension plan required first:** Per-model `data_paths` override. This plan cannot execute until that flat_record enhancement is complete.

Create the flat_record plan at: `~/.local/share/ppm/gems/flat_record/docs/extensions/plan-04-per-model-data-paths.md`

## Test Spec

### `spec/pim/models/profile_shared_spec.rb`

```ruby
# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Profile shared data loading" do
  let(:shared_dir) { Dir.mktmpdir("provisioning") }
  let(:project_dir) { Dir.mktmpdir("pim-project") }

  before do
    # Write shared profiles
    File.write(File.join(shared_dir, "profiles.yml"), YAML.dump([
      { "id" => "default", "hostname" => "shared-host", "username" => "admin", "timezone" => "UTC" },
      { "id" => "dev", "parent_id" => "default", "hostname" => "dev-host" }
    ]))

    # Configure Profile to use shared + project paths
    Pim::Profile.data_paths = [shared_dir, File.join(project_dir, "data")]
    Pim::Profile.store.reload!
  end

  after do
    FileUtils.remove_entry(shared_dir)
    FileUtils.remove_entry(project_dir)
  end

  it "loads profiles from shared directory" do
    profiles = Pim::Profile.all
    expect(profiles.map(&:id)).to include("default", "dev")
  end

  it "resolves parent chain from shared profiles" do
    dev = Pim::Profile.find("dev")
    expect(dev.resolved_attributes["hostname"]).to eq("dev-host")
    expect(dev.resolved_attributes["username"]).to eq("admin")
  end

  context "with project-level overrides" do
    before do
      project_data = File.join(project_dir, "data")
      FileUtils.mkdir_p(project_data)
      File.write(File.join(project_data, "profiles.yml"), YAML.dump([
        { "id" => "default", "hostname" => "project-host" }
      ]))
      Pim::Profile.store.reload!
    end

    it "merges project profile over shared profile" do
      profile = Pim::Profile.find("default")
      expect(profile.hostname).to eq("project-host")   # overridden
      expect(profile.username).to eq("admin")           # inherited from shared
    end
  end

  context "with no project data directory" do
    before do
      Pim::Profile.data_paths = [shared_dir]
      Pim::Profile.store.reload!
    end

    it "loads profiles from shared directory only" do
      profiles = Pim::Profile.all
      expect(profiles.map(&:id)).to include("default")
    end
  end
end
```

## Verification

```bash
# FlatRecord enhancement complete (prerequisite)
# Profile loads from shared path
bundle exec rspec spec/pim/models/profile_shared_spec.rb

# All existing specs pass
bundle exec rspec

# Manual verification
mkdir -p ~/.local/share/provisioning
cp my-project/data/profiles.yml ~/.local/share/provisioning/profiles.yml
cd my-project
pim profile list    # should show shared profiles
pim profile show default  # should show shared profile data
```
