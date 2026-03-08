---
---

# Plan 06: FlatRecord Integration and Get/Set API

## Context

Read these files before starting:

- `lib/pim.rb` — `Pim::Config`, `Pim::Profile`, XDG constants (after plan-04)
- `lib/pim/profile.rb` — `Pim::ProfileConfig`, `Pim::ProfileManager`
- `lib/pim/iso.rb` — `Pim::IsoConfig`, `Pim::IsoManager`
- `lib/pim/build.rb` — `Pim::BuildConfig`, `Pim::BuildManager`
- `lib/pim/registry.rb` — `Pim::Registry`
- `lib/pim/cli.rb` — Dry::CLI registry
- `lib/pim/commands/profile/` — current list/show/add commands
- `lib/pim/commands/iso/` — current list/download/verify/add commands
- `lib/pim/commands/build/` — current list/show/run/clean/status commands
- `lib/pim/templates/project/` — scaffold templates

**Prerequisites:**
- Plan 04 (namespace consolidation) must be complete
- FlatRecord extension `plan-01-read-only-multi-path` must be complete (provides `data_paths`, `read_only`, `merge_strategy`)

## Objective

1. Drop the `.d/` directory pattern for data collections — use one YAML file per model
2. Define FlatRecord models for profiles, ISOs, and builds
3. Configure FlatRecord with `data_paths` (global `~/.config/pim` + project dir) and `deep_merge`
4. Replace `list`/`show` commands with a uniform `get [ID] [FIELD]` API
5. Keep `add` and `remove` commands where appropriate
6. Remove the old `ProfileConfig`, `IsoConfig`, and their Manager classes — FlatRecord replaces them

## Design decisions

### New project layout

```
myproject/
├── pim.yml                  # Project config (build settings, serve defaults, ventoy)
├── profiles.yml             # Profile records
├── isos.yml                 # ISO catalog records
├── builds.yml               # Build definition records (future)
├── preseeds.d/              # Template files (not data — keep .d/)
│   └── default.cfg.erb
├── installs.d/
│   └── default.sh
├── scripts.d/
│   ├── base.sh
│   └── finalize.sh
└── verifications.d/
    └── default.sh
```

Global defaults at `~/.config/pim/`:

```
~/.config/pim/
├── profiles.yml             # Personal defaults (username, ssh key, timezone)
└── isos.yml                 # Personal ISO catalog (optional)
```

**Note:** `pim.yml` is NOT loaded through FlatRecord — it's project configuration, not record data. `Pim::Config` continues to read `pim.yml` directly. Only `profiles.yml`, `isos.yml`, and `builds.yml` are FlatRecord models.

### FlatRecord configuration

```ruby
FlatRecord.configure do |c|
  c.backend = :yaml
  c.data_paths = [
    File.join(Pim::XDG_CONFIG_HOME, "pim"),  # ~/.config/pim (global)
    Pim::Project.root!                         # project dir (local)
  ]
  c.read_only = true          # PIM chooses read-only; FlatRecord does not auto-infer
  c.merge_strategy = :deep_merge
  c.id_strategy = :string     # IDs are human-readable names like "default", "developer"
end
```

### FlatRecord models

**`Pim::Profile` (replaces existing class):**

```ruby
module Pim
  class Profile < FlatRecord::Base
    source "profiles"    # reads profiles.yml

    attribute :id, :string                    # profile name: "default", "developer"
    attribute :hostname, :string
    attribute :username, :string
    attribute :password, :string
    attribute :timezone, :string
    attribute :domain, :string
    attribute :locale, :string
    attribute :keyboard, :string
    attribute :packages, :string              # space-separated or array
    attribute :authorized_keys_url, :string

    # Template resolution (keep from existing Profile class)
    def preseed_template(name = nil)
      name ||= id
      find_template('preseeds.d', "#{name}.cfg.erb") ||
        (name != 'default' && find_template('preseeds.d', 'default.cfg.erb'))
    end

    def install_template(name = nil)
      name ||= id
      find_template('installs.d', "#{name}.sh") ||
        (name != 'default' && find_template('installs.d', 'default.sh'))
    end

    def verification_script(name = nil)
      name ||= id
      find_template('verifications.d', "#{name}.sh") ||
        (name != 'default' && find_template('verifications.d', 'default.sh'))
    end

    private

    def find_template(subdir, filename)
      project_path = File.join(Pim::Project.root!, subdir, filename)
      return project_path if File.exist?(project_path)
      nil
    end
  end
end
```

**`Pim::Iso` (new model, replaces IsoConfig data):**

```ruby
module Pim
  class Iso < FlatRecord::Base
    source "isos"        # reads isos.yml

    attribute :id, :string                    # key: "debian-13.3.0"
    attribute :name, :string
    attribute :url, :string
    attribute :checksum, :string
    attribute :checksum_url, :string
    attribute :filename, :string
    attribute :architecture, :string
  end
end
```

**`Pim::Build` (future — registry entries as FlatRecord):**

Not in this plan. The registry is structurally different (keyed by `profile-arch`, written during builds). Keep `Pim::Registry` as-is for now. The `build get` command reads from the registry directly.

### YAML file format change

Current `profiles.d/default.yml`:

```yaml
default:
  hostname: pim
  username: ansible
  password: ansible
```

New `profiles.yml` (FlatRecord collection format):

```yaml
---
- id: default
  hostname: pim
  username: ansible
  password: ansible
- id: developer
  hostname: dev
  packages: vim git curl
```

This is the standard FlatRecord collection layout — an array of hashes, each with an `id` field.

Same for `isos.yml`:

```yaml
---
- id: debian-13.3.0
  name: Debian 13.3.0
  url: https://cdimage.debian.org/...
  checksum: sha256:abc123...
  filename: debian-13.3.0-arm64-netinst.iso
  architecture: arm64
```

### Unified get/set command pattern

Every resource gets a `get` command with progressive detail by arity:

```
pim profile get                      # list all (table format)
pim profile get default              # show all fields for 'default'
pim profile get default hostname     # just the value: "pim"

pim iso get                          # list all ISOs
pim iso get debian-13.3.0            # show all fields
pim iso get debian-13.3.0 url        # just the URL

pim build get                        # list all built images
pim build get default                # show image details
pim build get default path           # just the image path
```

`set` is NOT implemented (read-only FlatRecord). `add` and `remove` are also deferred — they require write support. Keep placeholders that explain they're not yet available.

### Commands to remove

- `profile list` → replaced by `profile get`
- `profile show NAME` → replaced by `profile get NAME`
- `iso list` → replaced by `iso get`
- `build list` → replaced by `build get`
- `build show PROFILE` → replaced by `build get PROFILE`

Keep `profile ls` and `iso ls` as aliases for `profile get` and `iso get`.

### Commands to keep unchanged

- `iso download`, `iso verify`, `iso add` — these are operations, not CRUD
- `build run`, `build clean`, `build status` — same
- `config get/set` — different semantics (dot-notation into pim.yml, not records)

## Implementation

### 1. Add flat_record dependency

In `pim.gemspec`:

```ruby
spec.add_dependency "flat_record"
```

### 2. FlatRecord configuration in PIM

Create `lib/pim/models.rb` that configures FlatRecord and requires the model files:

```ruby
require "flat_record"

module Pim
  def self.configure_flat_record!(project_dir: nil)
    project_dir ||= Pim::Project.root!

    FlatRecord.configure do |c|
      c.backend = :yaml
      c.data_paths = [
        File.join(Pim::XDG_CONFIG_HOME, "pim"),
        project_dir
      ]
      c.merge_strategy = :deep_merge
      c.id_strategy = :string
    end
  end
end

require_relative "models/profile"
require_relative "models/iso"
```

### 3. Create model files

Create `lib/pim/models/profile.rb` and `lib/pim/models/iso.rb` with the FlatRecord model definitions shown above.

### 4. Update scaffold templates

Replace `profiles.d/default.yml` with `profiles.yml` in the scaffold template. Replace `isos.d/default.yml` with `isos.yml`. Remove the `.d/` directories for data from `Pim::Project::SCAFFOLD_DIRS`.

Keep `preseeds.d/`, `installs.d/`, `scripts.d/`, `verifications.d/` — these are template directories, not data.

### 5. Create get commands

Create `lib/pim/commands/profile/get.rb`:

```ruby
module Pim
  module Commands
    class Profile < Dry::CLI::Command
      class Get < Dry::CLI::Command
        desc "Show profile information"

        argument :id, required: false, desc: "Profile name"
        argument :field, required: false, desc: "Field name"

        def call(id: nil, field: nil, **)
          Pim.configure_flat_record!

          if id.nil?
            list_all
          elsif field.nil?
            show_record(id)
          else
            show_field(id, field)
          end
        end

        private

        def list_all
          profiles = Pim::Profile.all
          if profiles.empty?
            puts "No profiles. Add profiles to profiles.yml."
            return
          end
          # Table output with key fields
          profiles.each do |p|
            puts "#{p.id}  #{p.hostname || '-'}  #{p.username || '-'}"
          end
        end

        def show_record(id)
          profile = Pim::Profile.find(id)
          Pim::Profile.attribute_names.each do |name|
            value = profile.send(name)
            puts "#{name}: #{value}" unless value.nil?
          end
        end

        def show_field(id, field)
          profile = Pim::Profile.find(id)
          unless Pim::Profile.attribute_names.include?(field)
            Pim.exit!(1, message: "Unknown field '#{field}'. Valid: #{Pim::Profile.attribute_names.join(', ')}")
          end
          puts profile.send(field)
        end
      end
    end
  end
end
```

Same pattern for `iso/get.rb` and `build/get.rb` (build reads from Registry, not FlatRecord).

### 6. Update CLI registry

```ruby
# Remove
# register "profile list", ...
# register "profile show", ...

# Add
register "profile get",    Commands::Profile::Get
register "profile ls",     Commands::Profile::Get   # alias

register "iso get",        Commands::Iso::Get
register "iso ls",         Commands::Iso::Get

register "build get",      Commands::Build::Get
register "build ls",       Commands::Build::Get
```

### 7. Remove old classes

After migration is complete:

- Remove `Pim::ProfileConfig` (was in `lib/pim/profile.rb`)
- Remove `Pim::ProfileManager` (was in `lib/pim/profile.rb`)
- Remove `Pim::IsoConfig` (was in `lib/pim/iso.rb`)
- Remove `Pim::IsoManager` — partially. Keep the download/verify logic but refactor it to work with `Pim::Iso` model instead of the old config hash.

The download and verify operations on ISOs need the model attributes (url, checksum, filename). Refactor `IsoManager` (or rename to `Pim::IsoDownloader` or similar) to accept a `Pim::Iso` record:

```ruby
Pim::IsoDownloader.download(iso)   # iso is a Pim::Iso FlatRecord instance
Pim::IsoDownloader.verify(iso)
```

### 8. Update Pim::Config

`Pim::Config` no longer needs `.profiles` or `.iso` sub-config accessors for data. It still needs:

- `.build` → `Pim::BuildConfig` (reads pim.yml `build` section)
- `.ventoy` → `Pim::VentoyConfig` (reads pim.yml `ventoy` section)
- `.serve_defaults` → from pim.yml `serve` section
- `.profile(name)` → convenience, now delegates to `Pim::Profile.find(name)`
- `.profile_names` → convenience, now `Pim::Profile.all.map(&:id)`

### 9. Update global config directory

Create `~/.config/pim/profiles.yml` with personal defaults (or document how to create it). The scaffold template should mention this in a comment in the generated `profiles.yml`.

### 10. Update FlatRecord initialization in commands

Commands that use FlatRecord models need to call `Pim.configure_flat_record!` before accessing models. This can be done in each command's `call` method, or in a shared before-hook. Consider a helper:

```ruby
# In command base or shared module
def with_project
  Pim.configure_flat_record!
  yield
end
```

## Test spec

### `spec/pim/models/profile_spec.rb`

- `Pim::Profile.all` returns all profiles from merged paths
- `Pim::Profile.find("default")` returns the default profile
- `Pim::Profile.find("nonexistent")` raises `FlatRecord::RecordNotFound`
- Global profile fields are available when project profile doesn't override them
- Project profile fields override global profile fields (deep merge)
- `profile.preseed_template` resolves template path
- `profile.install_template` resolves template path
- `profile.verification_script` resolves template path
- `Pim::Profile.all` is read-only (save raises `FlatRecord::ReadOnlyError`)

### `spec/pim/models/iso_spec.rb`

- `Pim::Iso.all` returns all ISOs
- `Pim::Iso.find("debian-13.3.0")` returns the ISO record
- Attributes are accessible (url, checksum, filename, architecture)
- Read-only (save raises)

### `spec/pim/commands/profile/get_spec.rb`

- No args: lists all profiles
- With ID: shows all fields for that profile
- With ID and field: shows just the field value
- Unknown ID: error message
- Unknown field: error with valid field list

### `spec/pim/commands/iso/get_spec.rb`

- Same pattern as profile get

### `spec/pim/commands/build/get_spec.rb`

- No args: lists all built images from registry
- With profile name: shows image details
- With profile and field: shows just that field

## Verification

```bash
# All specs pass
bundle exec rspec

# No .d/ data directories in scaffold
ls lib/pim/templates/project/   # should have profiles.yml, isos.yml, not profiles.d/

# FlatRecord models work
cd /path/to/project
pim c
pim> Pim.configure_flat_record!
pim> Profile.all
pim> Profile.find("default")
pim> Profile.find("default").hostname
pim> Iso.all

# Get commands work
pim profile get
pim profile get default
pim profile get default hostname
pim iso get
pim iso get debian-13.3.0
pim iso get debian-13.3.0 url
pim build get
pim build get default

# Aliases work
pim profile ls
pim iso ls
pim build ls

# Read-only enforced
pim c
pim> p = Profile.find("default")
pim> p.hostname = "changed"
pim> p.save   # => raises FlatRecord::ReadOnlyError

# Old commands removed
pim profile list   # should not exist (or alias to get)
pim profile show default  # should not exist

# Global merge works
cat ~/.config/pim/profiles.yml   # has username, timezone
cat ./profiles.yml               # has hostname, packages
pim profile get default          # shows merged fields from both
```
