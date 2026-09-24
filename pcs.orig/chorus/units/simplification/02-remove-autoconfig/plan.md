---
---

# Plan 02 — Remove AutoConfig

## Objective

Remove `FlatRecordConfig` module, `AutoConfigStore` mixin, and `Profile::SHARED_PROFILES_DIR`. FlatRecord is now configured entirely by `boot!`. Profile data_paths are user-controlled via `pcs.rb`.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pcs/lib/pcs/flat_record_config.rb` — FlatRecordConfig and AutoConfigStore (to be deleted)
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/site.rb` — uses `extend Pcs::AutoConfigStore`
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/host.rb` — uses `extend Pcs::AutoConfigStore`
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/service.rb` — uses `extend Pcs::AutoConfigStore`
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/profile.rb` — has SHARED_PROFILES_DIR, has `data_paths`

## Implementation

### 1. Delete `lib/pcs/flat_record_config.rb`
### 2. Remove `extend Pcs::AutoConfigStore` from all models
### 3. Clean up Profile — remove `SHARED_PROFILES_DIR` and hardcoded `data_paths`
### 4. Verify boot order
### 5. Remove any remaining references

## Verification

1. `bundle exec rspec` — all green
2. Grep: no `FlatRecordConfig` in lib/
3. Grep: no `AutoConfigStore` in lib/
4. Grep: no `SHARED_PROFILES_DIR` in lib/
