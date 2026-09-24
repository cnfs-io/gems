---
---

# Plan 04 — DRAFT: Dissolve main.yml and Refactor Data Model

**STATUS: DRAFT — Not for execution. Captures design decisions from planning session. Will be decomposed into executable plans when activated.**

## Summary

`sites/main.yml` is eliminated entirely. Its contents are redistributed to proper homes: `pcs.rb` config, FlatRecord models (`Role`, `Service` with parent chain), and class-level defaults on host STI subclasses. `ProjectConfig` class is removed.

## What Was in main.yml and Where It Goes

| Was in main.yml | New home | Mechanism |
|---|---|---|
| `defaults.preseed_interface` | `Pcs::PveHost.default_preseed_interface` | Class attribute set in `pcs.rb` |
| `defaults.root_password` | Profile attribute | Already exists on Profile model |
| `defaults.timezone` | Profile attribute | Already exists on Profile model |
| `defaults.locale` | Profile attribute | Already exists on Profile model |
| `devices.*` (role -> type mapping) | `data/roles.yml` | New `Pcs::Role` FlatRecord model |
| `sites.domain` | `Pcs::Site.top_level_domain` | Class attribute set in `pcs.rb` |
| `sites.dns_fallback_resolvers` | `config.networking.dns_fallback_resolvers` | Nested config block in `pcs.rb` |
| `sites.ip_assignments` | `ip_base` attribute on Role model | In `data/roles.yml` |
| `sites.storage_subnet_offset` | `config.networking.storage_subnet_offset` | Nested config block in `pcs.rb` |
| `services.netbootxyz.*` | `data/services.yml` (parent record) | Service model with parent chain |
| `services.tailscale.*` | `data/services.yml` (parent record) | Service model with parent chain |
| `services.dnsmasq.*` | `data/services.yml` (parent record) | Service model with parent chain |

## New Models

### Pcs::Role
### Pcs::Service — Parent Chain Pattern

## Decomposition Into Plans (When Activated)

| # | Name | Scope |
|---|------|-------|
| 01 | role-model | Create Pcs::Role, data/roles.yml, scaffold template, move ip_base logic |
| 02 | service-parent-chain | Add parent_id to Service, multi-path data_paths, data/services.yml |
| 03 | host-class-defaults | Add class_attribute defaults to PveHost (and other STI subclasses) |
| 04 | pcs-rb-networking | Add config.networking block, Site.top_level_domain |
| 05 | dissolve-main-yml | Remove ProjectConfig, update all services/commands, migration script |
| 06 | scaffold-update | Update pcs new to generate new layout |
