---
---

# Plan 03 — Update Scaffold

## Objective

Update `pcs new` to generate `pcs.rb` alongside the existing project structure. Update all command code that references `Project.*` or manually calls `Config.load` / `FlatRecordConfig.ensure_configured!` to use the new boot-based pattern.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/new.rb` — current scaffold command
- `~/.local/share/ppm/gems/pcs/lib/pcs/templates/project/` — current templates
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/*.rb` — all commands (audit for Project.* and Config.load calls)
- `~/.local/share/ppm/gems/pcs/lib/pcs/services/*.rb` — all services
- `~/.local/share/ppm/gems/pcs/lib/pcs/cli.rb` — CLI registry and require order

## Implementation

### 1. Create pcs.rb template
### 2. Update `pcs new` command
### 3. Audit and update all commands (replace Project.*, Config.load, FlatRecordConfig references)
### 4. Update console command
### 5. Update CLI dispatch (boot! for all commands except new/version)
### 6. Update exe/pcs

## Verification

1. `bundle exec rspec` — all green
2. `pcs new /tmp/test-simplification` creates project with `pcs.rb`
3. Grep: no `Pcs::Project` in lib/
4. Grep: no `FlatRecordConfig` in lib/
