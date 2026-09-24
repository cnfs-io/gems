---
---

# Plan 09 — Dissolve ProjectConfig and main.yml

## Objective

Remove `Pcs::ProjectConfig` class and `sites/main.yml`. All data previously in `ProjectConfig` now has proper homes (Role model, Service model, Config DSL networking, PveHost class defaults, Site.top_level_domain). Update all remaining consumers. Remove the file from scaffold. Update boot to no longer load it.

## Context — Read Before Starting

After plans 05-08, the remaining `ProjectConfig` consumers are:
- `boot.rb` — `@project_config = Pcs::ProjectConfig.load(@project_dir)`
- `commands/services_command.rb` — `Start`, `Restart` pass `config = Pcs.project_config`
- `commands/clusters_command.rb` — passes `config` to `Proxmox::Installer`
- `services/netboot_service.rb` — `config.defaults[:root_password]`, `config.ssh_key_path`
- `providers/proxmox/installer.rb` — `config.ssh_key_path`, `config.ssh_public_key`

## Implementation

### 1. Add SSH helper methods to Site
### 2. Add interim preseed defaults to Config DSL
### 3. Move discovery constants to adapter
### 4. Add `Pcs.load_provider_config(name)` utility
### 5. Update `NetbootService`
### 6. Update `DnsmasqService`
### 7. Update `Proxmox::Installer`
### 8. Update `TailscaleService`
### 9. Update commands
### 10. Remove `ProjectConfig`
### 11. Remove from CLI require chain
### 12. Remove from boot
### 13. Remove from scaffold
### 14. Update pcs.rb template

## Verification

1. `bundle exec rspec` — all green
2. Grep: no `ProjectConfig` in lib/
3. Grep: no `project_config` in lib/
4. Grep: no `main.yml` references in lib/
5. `pcs new /tmp/test-final` — no `sites/main.yml` generated
6. All commands work without ProjectConfig
