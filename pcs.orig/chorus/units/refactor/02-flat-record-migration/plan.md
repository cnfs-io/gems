---
---

# Refactor Plan 02: Replace Models with FlatRecord

## Goal

Replace the hand-rolled `Device`, `Services`, and `Site` models with `FlatRecord::Base` subclasses. All specs from Plan 01 must continue to pass — same public API, different persistence layer.

**Config and State are NOT refactored** — Config is read-only, State is a state machine.

## Prerequisites

- Plan 01 complete (rename done, all characterization specs green)
- Read the full refactor design doc at `docs/refactor-flat-record.md`
- Read flat_record's CLAUDE.md at `~/.local/share/ppm/gems/flat_record/CLAUDE.md`

## Steps

### Step 1: Add flat_record dependency

```ruby
# pcs.gemspec
spec.add_dependency "flat_record"
```

```ruby
# lib/pcs.rb — add to requires
require "flat_record"
```

### Step 2: Create FlatRecord initializer

Create `lib/pcs/flat_record_config.rb`:

```ruby
module Pcs
  module FlatRecordConfig
    def self.setup!(project_root = Pcs::Project.root)
      FlatRecord.configure do |config|
        config.backend = :yaml
        config.data_path = project_root.join("sites").to_s
        config.id_strategy = :integer
        config.enable_hierarchy(model: :site, key: :name)
      end
    end
  end
end
```

Integrate into CLI boot path — call `setup!` before any model access.

Update the spec helper to call `Pcs::FlatRecordConfig.setup!` after creating the tmpdir project. This replaces the manual `Pcs::Project` stubs.

### Step 3: Rewrite Site model

Replace `lib/pcs/models/site.rb` with a FlatRecord::Base subclass.

The Site is the **hierarchy parent**. FlatRecord discovers sites by scanning subdirectories of `data_path` (`sites/`). Each subdirectory name becomes the Site's `name` attribute (the hierarchy key). Site-specific attributes (domain, timezone, networks) come from the enrichment file or from `site.yml` in the subdirectory.

**Key concern:** FlatRecord's hierarchy parent loads enrichment from a top-level `sites.yml`, but PCS stores site config in `sites/<name>/site.yml`. Investigate whether FlatRecord can be configured to load per-directory enrichment, or whether we need to:
- Option A: Create a top-level `sites/sites.yml` with all site data (breaks the current per-site file convention)
- Option B: Override the store's load behavior for the hierarchy parent
- Option C: Load `site.yml` in an `after_initialize` callback that reads the file manually

Pick the approach that preserves the current file layout. Document the decision.

**Public API to preserve:**
- `Site.load(site_name)` -> `Site.find_by(name: site_name)` (or add a `self.load` class method for backward compat)
- `site.get(:domain)` -> `site.domain`
- `site.network(:compute)` -> keep as a method, delegates to networks hash
- `site.update(:field, value)` -> `site.update(field: value)`
- `site.save!` -> `site.save!`

If the Plan 01 specs used the old API (`site.get(:domain)`), update them to use attribute accessors (`site.domain`). This is an intentional API improvement — document it.

### Step 4: Rewrite Device model

Replace `lib/pcs/models/device.rb` with a FlatRecord::Base subclass.

Device is a **hierarchy child**. FlatRecord loads `sites/<site>/devices.yml` and injects `site_id` as the foreign key.

**Data format:** Current `devices.yml` wraps records in a `devices:` key: `{devices: [{id: 1, ...}]}`. FlatRecord expects a bare array: `[{id: 1, ...}]`. The migration must unwrap this. Update the fixture helper in spec too.

**Public API mapping:**

| Old (Plan 01 specs) | New |
|---------------------|-----|
| `Device.load(site_name)` | `Device.where(site_id: site_name)` or keep `self.load` as sugar |
| `device_collection.all` | `Device.where(site_id: site_name).to_a` |
| `device_collection.find(id)` | `Device.find(id)` |
| `device_collection.find_by_mac(mac)` | `Device.find_by(mac: mac)` — handle case insensitivity |
| `device_collection.find_by_ip(ip)` | `Device.find_by(discovered_ip: ip)` |
| `device_collection.update(id, field, val)` | `Device.find(id).update(field => val)` |
| `device_collection.merge_scan(results)` | `Device.merge_scan(site_name, results)` class method |
| `device_collection.save!` | individual record saves (automatic with FlatRecord) |
| `device_collection.hosts_of_type(type)` | `Device.where(type: type, site_id: site_name)` |
| `device_collection.next_id` | FlatRecord handles ID generation |

**Update Plan 01 specs** to use the new API. The specs test the same behavior, just through FlatRecord's interface. This is expected — the point of characterization specs is to verify behavior, and the behavior is preserved even if the calling convention changes slightly.

### Step 5: Rewrite Service model

Replace `lib/pcs/models/services.rb` with a FlatRecord::Base subclass.

**Data format migration:** Current `services.yml` is a hash keyed by service name:
```yaml
tailscale:
  auth_key:
  status: unconfigured
```

FlatRecord needs an array of records:
```yaml
- id: "1"
  name: tailscale
  auth_key:
  status: unconfigured
```

**Public API mapping:**

| Old | New |
|-----|-----|
| `Services.load(site_name)` | `Service.where(site_id: site_name)` |
| `services.all` | `Service.where(site_id: site_name)` returns Relation |
| `services.find(:dnsmasq)` | `Service.find_by(name: "dnsmasq", site_id: site_name)` |
| `services.update(name, field, val)` | `Service.find_by(name: name).update(field => val)` |
| `services.save!` | automatic with FlatRecord |

### Step 6: Data migration script

Create `bin/pcs-migrate` that converts an existing PCS project:

1. For each site directory:
   - Unwrap `devices.yml` from `{devices: [...]}` to bare `[...]`
   - Convert `services.yml` from hash-keyed to array-of-records format
   - Leave `site.yml` as-is (loaded by hierarchy enrichment or custom logic)
2. Print summary of changes

### Step 7: Update commands and services

Mechanically update all files that reference the old model API to use the new FlatRecord-backed models. See the mapping tables above.

Key files:
- `commands/device/scan.rb`
- `commands/device/get.rb`
- `commands/device/set.rb`
- `commands/service/get.rb`
- `commands/service/set.rb`
- `commands/site/use.rb`, `site/get.rb`, `site/set.rb`
- `services/control_plane_service.rb`
- `services/dnsmasq_service.rb`
- `services/netboot_service.rb`
- `services/tailscale_service.rb`

### Step 8: Remove old code

Delete any remaining old model code that's been fully replaced.

## Verification

```bash
cd ~/.local/share/ppm/gems/pcs
bundle exec rspec
```

All Plan 01 specs pass (with updated API calls where noted). The refactor is complete.

## Risks & Investigation Notes

1. **Hash attributes** — FlatRecord's YAML backend handles hashes, but ActiveModel::Attributes may not have a `:hash` type. Test whether `attribute :networks` with no type, or a custom type, works correctly. If not, store networks as raw data loaded in a callback.

2. **Hierarchy parent enrichment** — FlatRecord loads parent enrichment from a top-level file, not per-directory. The Site model may need custom loading. See Step 3 options.

3. **devices.yml wrapper key** — Current files use `{devices: [...]}`. FlatRecord expects bare arrays. The migration handles this, but the fixture helper needs updating too.

4. **Case-insensitive MAC lookup** — `Device.find_by(mac: mac)` is exact match in FlatRecord. If case-insensitive matching is needed, add a `find_by_mac` class method that normalizes.

5. **FlatRecord reload between tests** — FlatRecord caches records in the Store. Ensure `FlatRecord::Base` subclasses call `reload!` between specs, or that the store is reset. The spec helper should handle this.
