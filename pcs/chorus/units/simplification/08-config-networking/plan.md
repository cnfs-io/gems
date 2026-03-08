---
---

# Plan 08 — Config Networking and Site.top_level_domain

## Objective

Add `config.networking` nested block to `Pcs::Config` DSL. Move `dns_fallback_resolvers` and `storage_subnet_offset` from `ProjectConfig` to the config DSL. Add `Pcs::Site.top_level_domain` class attribute. Update `pcs.rb` template and scaffold.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pcs/lib/pcs/config.rb` — Config DSL class
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/config.rb` — `ProjectConfig`
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/site.rb` — Site model
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/sites_command.rb` — `SitesCommand::Add`

## Implementation

### 1. Add `NetworkingSettings` class and `networking` method to Config
### 2. Add `top_level_domain` class attribute to Site
### 3. Add networking helper methods (derive_storage_subnet, derive_storage_gateway on Site)
### 4. Update `SitesCommand::Add`
### 5. Remove `config = Pcs.project_config` where possible
### 6. Update pcs.rb template
### 7. Update scaffold

## Verification

1. `bundle exec rspec` — all green
2. `Pcs.config.networking.dns_fallback_resolvers` returns configured values
3. `Pcs::Site.top_level_domain` returns domain from pcs.rb
