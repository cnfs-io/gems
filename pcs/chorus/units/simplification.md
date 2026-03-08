---
objective: "Align PCS's initialization and configuration patterns with PIM. Add a pcs.rb Ruby DSL config file as the project marker. Introduce Pcs.root, Pcs.boot!, Pcs.configure."
status: complete
---

# Simplification Tier — PCS

## Objective

Align PCS's initialization and configuration patterns with PIM. Add a `pcs.rb` Ruby DSL config file as the project marker. Introduce `Pcs.root`, `Pcs.boot!`, `Pcs.configure`. Remove `FlatRecordConfig`, `AutoConfigStore`, `Project` module, and ultimately `ProjectConfig` and `main.yml`.

**The question this tier answers:** Can PCS boot cleanly from a single `pcs.rb` config block, with all data in proper models and no monolithic YAML config file?

## Background

PCS originally had:
- `Pcs::Project` module — project detection, site selection, path helpers
- `Pcs::FlatRecordConfig` — separate module to configure FlatRecord with lazy initialization
- `Pcs::AutoConfigStore` — mixin hack for auto-config on first model access
- `Pcs::ProjectConfig` — god object reading `sites/main.yml`, merging 5 sets of hardcoded defaults
- `sites/main.yml` — monolithic YAML with device roles, IP assignments, service config, preseed defaults, SSH config, provider selections

After this tier:
- `pcs.rb` is the project marker and Ruby DSL config file
- `Pcs.root`, `Pcs.root!`, `Pcs.boot!` on the top-level module
- `Pcs.configure` block with nested `flat_record` and `networking` blocks
- `Pcs::Role` model in `data/roles.yml` (device roles + IP base octets)
- `Pcs::Service` with parent chain (project-wide definitions + per-site state)
- `Pcs::Site.top_level_domain` class attribute set in `pcs.rb`
- `Pcs::PveHost.default_preseed_interface` class defaults set in `pcs.rb`
- SSH key paths derived from Site model
- No `Project` module, no `FlatRecordConfig`, no `AutoConfigStore`
- No `ProjectConfig` class, no `sites/main.yml`

## Plans

### Phase 1 — Boot and Config (Complete)

| # | Name | Description | Status |
|---|------|-------------|--------|
| 01 | boot-and-root | `Pcs.root`, `Pcs.boot!`, `Pcs.configure`. Dissolve Project module. Rename Config -> ProjectConfig. | complete |
| 02 | remove-autoconfig | Delete FlatRecordConfig, AutoConfigStore, SHARED_PROFILES_DIR. | complete |
| 03 | update-scaffold | `pcs new` generates `pcs.rb`. Update commands to use boot. | complete |

### Phase 2 — Dissolve main.yml

| # | Name | Description | Status |
|---|------|-------------|--------|
| 04 | config-model-draft | Design document capturing decomposition decisions. | complete |
| 05 | role-model | Create `Pcs::Role` in `data/roles.yml`. Move device roles + IP base octets. | pending |
| 06 | service-parent-chain | Service parent_id, multi-path data_paths, `data/services.yml`. | pending |
| 07 | host-class-defaults | PveHost class defaults for preseed_interface, preseed_device. | pending |
| 08 | config-networking | `config.networking` block, `Site.top_level_domain`, storage subnet helpers. | pending |
| 09 | dissolve-project-config | Remove ProjectConfig, main.yml, update all consumers. | pending |

## Project Layout After Completion

```
my-project/
  pcs.rb                          # Ruby DSL config (project marker)
  .env                            # PCS_SITE=rok (gitignored)
  .gitignore
  Gemfile
  README.md

  data/                           # project-wide data (non-hierarchical)
    roles.yml                     # Role definitions
    services.yml                  # Service definitions (parent records)

  sites/                          # per-site hierarchical data
    rok/
      site.yml                    # domain, timezone, ssh_key, networks
      hosts.yml                   # host inventory
      services.yml                # per-site service state (children)

  config/                         # provider-specific YAML (optional)
    tailscale.yml
```

## Completion Criteria

- `pcs.rb` is the project marker
- `Pcs.root` returns Pathname
- `Pcs.boot!` is the single entry point
- No `Project` module, `FlatRecordConfig`, `AutoConfigStore`
- No `ProjectConfig` class, no `sites/main.yml`
- `Pcs::Role` model with roles and IP base octets
- `Pcs::Service` with parent chain across `data/` and `sites/`
- `Pcs::PveHost` class defaults for preseed fields
- `config.networking` block for DNS and storage subnet offset
- `Pcs::Site.top_level_domain` for project domain
- SSH paths derived from Site model
- All specs pass
