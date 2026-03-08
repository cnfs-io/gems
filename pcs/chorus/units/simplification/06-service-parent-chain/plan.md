---
---

# Plan 06 — Service Parent Chain

## Objective

Add parent_id support to `Pcs::Service`. Create project-wide service definitions in `data/services.yml` as parent records. Per-site service records in `sites/<site>/services.yml` become children that inherit config from the parent. Eliminate the need for a separate `ServiceConfig` model — one model, two data locations, parent chain resolution.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pcs/lib/pcs/models/service.rb` — current Service model (per-site only)
- `~/.local/share/ppm/gems/pcs/lib/pcs/services/netboot_service.rb` — reads `config.services["netbootxyz"]`
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/services_command.rb` — Start/Restart pass `config` to services
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/sites_command.rb` — `SitesCommand::Add` creates default services

## Design

Multi-path data_paths: Service loads from both `data/` (parents) and `sites/` (children). Parent chain resolution via `resolved_attributes`.

## Implementation

### 1. Update Service model with parent chain support
### 2. Set Service data_paths in boot
### 3. Create services template
### 4. Update scaffold
### 5. Update `SitesCommand::Add`
### 6. Update `NetbootService`
### 7. Update `DnsmasqService`
### 8. Update `ServicesCommand::Start` and `::Restart`

## Verification

1. `bundle exec rspec` — all green
2. `Pcs::Service.find_by_name("netbootxyz").resolve(:image)` returns the container image
3. `pcs service list` shows services with status
