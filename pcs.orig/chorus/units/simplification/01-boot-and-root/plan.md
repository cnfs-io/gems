---
---

# Plan 01 — Boot and Root

## Objective

Add `Pcs.root`, `Pcs.root!`, `Pcs.boot!`, `Pcs.configure` with nested FlatRecord config block. Dissolve `Pcs::Project` module, absorbing its responsibilities into `Pcs` top-level methods.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pcs/lib/pcs.rb` — main module (very sparse right now)
- `~/.local/share/ppm/gems/pcs/lib/pcs/project.rb` — Project module (to be dissolved)
- `~/.local/share/ppm/gems/pcs/lib/pcs/flat_record_config.rb` — FlatRecordConfig (will be replaced in Plan 02, but understand it)
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/config.rb` — Config model (unchanged, but understand how it's loaded)
- `~/.local/share/ppm/gems/pim/lib/pim/boot.rb` — PIM's boot for reference pattern
- `~/.local/share/ppm/gems/pim/lib/pim/config.rb` — PIM's config for reference pattern

## Implementation

### 1. Create `lib/pcs/boot.rb`

`Pcs.root`, `Pcs.root!`, `Pcs.project_dir`, `Pcs.sites_dir`, `Pcs.site_dir`, `Pcs.states_dir`, `Pcs.state_dir`, `Pcs.site`, `Pcs.boot!`, `Pcs.reset!`

### 2. Create `lib/pcs/config.rb` (DSL config)

`Pcs::Config` DSL with `FlatRecordSettings` nested block.

### 3. Rename `Pcs::Config` (model) -> `Pcs::ProjectConfig`

### 4. Delete `lib/pcs/project.rb`

### 5. Update all `Pcs::Project.*` callers

### 6. Update `lib/pcs.rb` main module file

### 7. Update CLI to use boot

## Verification

1. `bundle exec rspec` — all green
2. Grep: no `Pcs::Project` references in lib/
3. `Pcs.root` returns Pathname
4. `Pcs.boot!` configures FlatRecord correctly
