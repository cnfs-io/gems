---
---

# Plan 05 — Role Model

## Objective

Create `Pcs::Role` FlatRecord model in `data/roles.yml`. Move device-type mapping and IP base octet assignments from `ProjectConfig` to this model. Update the scaffold to generate `data/roles.yml`. Update `HostsCommand::Set` to read roles from the model instead of `project_config.device_roles`.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pcs/lib/pcs/models/config.rb` — `ProjectConfig`: `device_roles`, `device_types`, `host_octet` methods
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/hosts_command.rb` — `HostsCommand::Set#interactive_configure`
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/sites_command.rb` — `SitesCommand::Add`
- `~/.local/share/ppm/gems/pcs/lib/pcs/boot.rb` — `apply_flat_record_config!`

## Design

Role is a non-hierarchical, read-only, collection-layout model. Uses per-model `data_paths` pointing at `data/`.

## Implementation

### 1. Create `lib/pcs/models/role.rb`
### 2. Create `data/` directory convention (update boot)
### 3. Add Role to CLI require chain
### 4. Add Role to reload
### 5. Update `HostsCommand::Set`
### 6. Update scaffold
### 7. Create roles template

## Verification

1. `bundle exec rspec` — all green
2. `pcs host set` interactive mode shows roles from `data/roles.yml`
3. `Pcs::Role.all` in console returns role records
