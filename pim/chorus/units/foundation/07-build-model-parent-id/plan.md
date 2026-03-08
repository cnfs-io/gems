---
---

# Plan 07: Build Model, Profile parent_id, and Model Refinements

## Context

Read these files before starting:

- `lib/pim/models/profile.rb` — current `Pim::Profile` FlatRecord model
- `lib/pim/models/iso.rb` — current `Pim::Iso` FlatRecord model
- `lib/pim/models.rb` — FlatRecord configuration
- `lib/pim/commands/build/get.rb` — current build get (reads from Registry)
- `lib/pim/commands/build/run.rb` — current build run (takes profile_name, arch)
- `lib/pim/registry.rb` — `Pim::Registry` for tracking built images
- `lib/pim/build.rb` — `Pim::BuildConfig`, `Pim::ArchitectureResolver`, etc.
- `lib/pim/build/manager.rb` — `Pim::BuildManager`
- `lib/pim/build/local_builder.rb` — `Pim::LocalBuilder`
- `lib/pim/templates/project/profiles.yml` — scaffold profile data
- `lib/pim/templates/project/isos.yml` — scaffold ISO data

**Prerequisites:**
- Plan 06 complete (FlatRecord integration, get API)

## Objective

1. Add `parent_id` to Profile for inheritance chains
2. Create a `Pim::Build` FlatRecord model that joins profile + ISO + distro/automation/build_method
3. Create `builds.yml` scaffold template
4. Update `build get` and `build run` to use the Build model
5. Move distro/automation concerns out of Profile and into Build where they belong

## Part 1: Profile parent_id

### Add `parent_id` attribute

In `lib/pim/models/profile.rb`:

```ruby
attribute :parent_id, :string
```

### Resolved profile (walks parent chain)

Add a method that walks the `parent_id` chain and deep merges:

```ruby
class Profile < FlatRecord::Base
  # Returns a hash with all attributes resolved through parent chain.
  # Child fields override parent fields. Deep merge for nested values.
  def resolved_attributes
    chain = parent_chain
    result = {}
    chain.each do |profile|
      result = result.deep_merge(profile.attributes.compact.except("id", "parent_id"))
    end
    result.merge("id" => id)
  end

  # Returns the resolved value for a field, walking up the parent chain
  def resolve(field)
    resolved_attributes[field.to_s]
  end

  # Returns the parent chain from root to self (oldest ancestor first)
  def parent_chain
    chain = [self]
    current = self
    seen = Set.new([id])  # cycle detection

    while current.parent_id
      raise "Circular parent_id reference: #{current.parent_id}" if seen.include?(current.parent_id)
      seen << current.parent_id
      current = self.class.find(current.parent_id)
      chain.unshift(current)
    end

    chain
  end

  def parent
    return nil unless parent_id
    self.class.find(parent_id)
  end
end
```

### Update `to_h` to use resolved attributes

The existing `to_h` returns raw attributes. Add `resolved_to_h` for the merged view, and update `to_h` to return resolved by default since that's what consumers (Server, Builder) expect:

```ruby
def to_h
  resolved_attributes
end

def raw_to_h
  attributes.compact
end
```

### Update `profile get` command

`pim profile get default` should show resolved attributes (after parent chain merge).
`pim profile get default --raw` could show only the fields set directly on this profile (optional).

### Example profiles.yml

```yaml
---
- id: default
  hostname: debian
  username: ansible
  password: changeme
  locale: en_US.UTF-8
  timezone: UTC
  packages: openssh-server curl sudo qemu-guest-agent

- id: dev
  parent_id: default
  packages: openssh-server curl sudo qemu-guest-agent vim git build-essential

- id: dev-roberto
  parent_id: dev
  authorized_keys_url: https://github.com/rjayroach.keys
  timezone: Asia/Singapore
```

### Update scaffold template

Update `lib/pim/templates/project/profiles.yml` to include a `parent_id` example.

## Part 2: Build model

### What a Build represents

A Build is a recipe that combines:
- **profile** — the machine personality (what gets installed)
- **iso** — the source media
- **distro** — the OS family (determines automation format)
- **automation** — preseed, kickstart, autoinstall, cloud-init
- **build_method** — how the image is built (qemu, iso-repack, cloud-import)
- **target** — where the result goes (local, proxmox, aws, iso) — added in plan 08

A Build does NOT store results (that's the Registry). It's a recipe, not a record of what happened.

### Model definition

Create `lib/pim/models/build.rb`:

```ruby
# frozen_string_literal: true

module Pim
  class Build < FlatRecord::Base
    source "builds"
    read_only true
    merge_strategy :deep_merge

    attribute :profile, :string              # references Profile#id
    attribute :iso, :string                  # references Iso#id
    attribute :distro, :string               # debian | ubuntu | rhel | fedora | alma
    attribute :automation, :string           # preseed | kickstart | autoinstall | cloud-init
    attribute :build_method, :string         # qemu | iso-repack | cloud-import
    attribute :arch, :string                 # target architecture (arm64, x86_64)
    attribute :target, :string               # references Target#id (plan 08, optional for now)
    attribute :disk_size, :string            # override BuildConfig default
    attribute :memory, :integer              # override BuildConfig default
    attribute :cpus, :integer                # override BuildConfig default

    # Resolve the profile (with parent chain)
    def resolved_profile
      Pim::Profile.find(profile)
    end

    # Resolve the ISO
    def resolved_iso
      Pim::Iso.find(iso)
    end

    # Sensible defaults
    def arch
      super || Pim::ArchitectureResolver.new.host_arch
    end

    def build_method
      super || "qemu"
    end

    def automation
      super || infer_automation
    end

    private

    def infer_automation
      case distro
      when "debian", "ubuntu" then "preseed"
      when "rhel", "fedora", "alma", "rocky" then "kickstart"
      else "preseed"  # default fallback
      end
    end
  end
end
```

### Register in models.rb

Add to `lib/pim/models.rb`:

```ruby
require_relative "models/build"
```

Update `configure_flat_record!` to reload:

```ruby
Pim::Build.reload!
```

### Scaffold template

Create `lib/pim/templates/project/builds.yml`:

```yaml
# PIM Build Recipes
# Each build combines a profile, ISO, and build method.
#
# Required fields:
#   profile: references a profile ID from profiles.yml
#   iso: references an ISO ID from isos.yml
#   distro: debian | ubuntu | rhel | fedora | alma
#
# Optional fields:
#   automation: preseed | kickstart | autoinstall | cloud-init (inferred from distro)
#   build_method: qemu | iso-repack | cloud-import (default: qemu)
#   arch: arm64 | x86_64 (default: host architecture)
#   target: references a target ID (future)
#   disk_size, memory, cpus: override global build config
---
[]
```

### Update project scaffolding

Add `builds.yml` to `Pim::Project` scaffold (copy from templates during `pim new`).

## Part 3: Update build commands

### `build get`

Replace the current registry-based `build get` with FlatRecord model access:

```
pim build get                    # list all build recipes
pim build get dev-debian         # show build recipe details
pim build get dev-debian profile # just the profile reference
```

For built image info (registry), add a separate section or command. Options:
- `pim build get dev-debian` shows both the recipe AND the latest build result from the registry
- `pim build status dev-debian` shows only the registry/result info (already exists)
- `pim image get` as a separate resource for built artifacts (future)

Recommendation: `build get` shows the recipe. `build status` shows the build result. Clean separation.

### `build run`

Currently: `pim build run PROFILE_NAME --arch x86_64`

New: `pim build run BUILD_ID`

```ruby
def call(build_id:, force: false, dry_run: false, vnc: nil, console: false, console_log: nil, **)
  Pim.configure_flat_record!
  
  build = Pim::Build.find(build_id)
  profile = build.resolved_profile
  iso = build.resolved_iso
  
  # Pass the build record to the manager instead of individual args
  manager = Pim::BuildManager.new
  manager.execute(build, profile: profile, iso: iso, force: force, ...)
end
```

### `build status`

Keep as-is — reads from Registry. Shows whether the image has been built, file path, size, cache key.

### `build clean`

Keep as-is — operates on built artifacts in Registry.

## Part 4: Remove distro-specific attributes from Profile

The Profile model currently has Debian-specific fields: `mirror_host`, `mirror_path`, `http_proxy`, `partitioning_method`, `partitioning_recipe`, `tasksel`, `grub_device`.

These are preseed-specific. They don't belong on Profile (which should be distro-agnostic). But they're needed by the preseed template.

Options:
- **A:** Move them to the Build model as override fields
- **B:** Keep them on Profile but document they're only used with preseed automation
- **C:** Move them to a separate `preseed_config` hash field on Build

Recommendation: **B for now.** These fields are profile-level settings (different machines get different partitioning). The Profile is the right place for "what this machine looks like." The fact that they're consumed by preseed templates is an implementation detail. A Kickstart template might need `root_password` or `selinux` — those would also go on Profile.

Keep all current Profile attributes. Add `parent_id`. Document that some fields are automation-specific.

## Test spec

### `spec/pim/models/profile_spec.rb` (additions)

- `parent_id` attribute is accessible
- `parent` returns the parent profile
- `parent` returns nil when no parent_id
- `parent_chain` returns [self] when no parent
- `parent_chain` returns [grandparent, parent, self] for chain
- `parent_chain` raises on circular reference
- `resolved_attributes` merges parent attributes
- `resolved_attributes` — child fields override parent
- `resolved_attributes` — grandparent -> parent -> child merge order
- `resolved_attributes` — fields only on parent are preserved
- `to_h` returns resolved attributes
- `raw_to_h` returns only directly-set attributes
- `resolve("hostname")` walks parent chain for specific field

### `spec/pim/models/build_spec.rb` (new)

- `Pim::Build.all` returns all build recipes
- `Pim::Build.find("dev-debian")` returns the build
- `build.resolved_profile` returns the Profile with parent chain resolved
- `build.resolved_iso` returns the Iso
- `build.arch` defaults to host architecture when not set
- `build.build_method` defaults to "qemu"
- `build.automation` inferred from distro when not set
- `build.automation` — debian -> preseed
- `build.automation` — fedora -> kickstart
- Read-only (save raises)

### `spec/pim/commands/build/get_spec.rb` (update)

- No args: lists all build recipes from FlatRecord
- With ID: shows build recipe details
- With ID and field: shows just that field

### `spec/pim/commands/build/run_spec.rb` (update)

- Takes build_id argument instead of profile_name
- Resolves profile and ISO from build record

## Verification

```bash
# All specs pass
bundle exec rspec

# Profile parent chain works
cd /path/to/project
pim c
pim> Profile.find("dev-roberto").parent_chain.map(&:id)
#=> ["default", "dev", "dev-roberto"]
pim> Profile.find("dev-roberto").to_h
#=> merged attributes from all three

# Build model works
pim> Build.all
pim> Build.find("dev-debian").resolved_profile.to_h
pim> Build.find("dev-debian").automation  #=> "preseed"

# Build get shows recipes
pim build get
pim build get dev-debian
pim build get dev-debian profile

# Build run uses build ID
pim build run dev-debian
```
