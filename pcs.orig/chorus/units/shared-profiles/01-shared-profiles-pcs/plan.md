---
---

# Plan 01 — Shared Profiles (PCS side)

## Objective

Add a FlatRecord-backed Profile model to PCS that reads from the shared XDG location, and update PCS's preseed template rendering to use this model instead of loose variables.

## Context

Read before starting:
- `lib/pcs/templates/netboot/preseed.cfg.erb` — current preseed template (uses loose variables)
- `lib/pcs/services/netboot_service.rb` — likely where preseed rendering happens
- `lib/pcs/flat_record_config.rb` — existing FlatRecord configuration
- `lib/pcs/models/` — existing models directory
- PIM's Profile model for reference: `~/.local/share/ppm/gems/pim/lib/pim/models/profile.rb`

## Implementation Spec

### Add flat_record dependency

If not already present, add `flat_record` to PCS's gemspec.

### `lib/pcs/models/profile.rb`

FlatRecord-backed Profile model with:
- Shared attributes (same as PIM): `parent_id`, `hostname`, `username`, `password`, `fullname`, `timezone`, `domain`, `locale`, `keyboard`, `packages`, `authorized_keys_url`
- PCS-specific attributes: `interface`, `device`
- Parent chain resolution via `parent_chain` and `resolved_attributes`
- Read-only, deep merge strategy

### Update preseed template rendering

Load profile, render with resolved attributes instead of loose variables.

### Design notes

- PCS Profile model duplicates parent_chain/resolved_attributes logic from PIM — intentional, no shared gem
- PCS-specific attributes declared in PCS's model only
- No project-level override for PCS — reads from shared only

## Verification

```bash
bundle exec rspec spec/pcs/models/profile_spec.rb
bundle exec rspec
```
