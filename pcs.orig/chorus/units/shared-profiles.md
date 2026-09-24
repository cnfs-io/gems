---
objective: "Configure PCS to read provisioning profiles from the shared XDG location at ~/.local/share/provisioning/profiles.yml."
status: complete
---

# Shared Profiles Tier — PCS

## Objective

Configure PCS to read provisioning profiles from the shared XDG location at `~/.local/share/provisioning/profiles.yml`. This gives PCS access to the same canonical profile data that PIM uses, enabling consistent preseed generation across both image-based and netboot workflows.

**The question this tier answers:** Can PCS use shared provisioning profiles to drive its preseed templates?

## Background

PCS currently injects profile data into preseed templates via loose variables (hostname, username, etc.) rather than a formal Profile model. PIM has a mature Profile model backed by FlatRecord with parent chain inheritance and deep merge.

By adding a FlatRecord-backed Profile model to PCS that reads from the shared location, PCS gets the same rich profile system: inheritance, deep merge, and a single source of truth shared with PIM.

## Prerequisites

1. **flat_record extension**: Per-model `data_paths` override must be complete (`~/.local/share/ppm/gems/flat_record/docs/extensions/plan-04-per-model-data-paths.md`)
2. **PIM shared profiles**: PIM's profiles migrated to `~/.local/share/provisioning/profiles.yml` (PIM's `docs/shared-profiles/plan-01-shared-profiles-pim.md`)
3. **PCS uses FlatRecord**: PCS must have flat_record as a dependency

## Plans

| # | Name | Description |
|---|------|-------------|
| 01 | shared-profiles-pcs | Add Profile model to PCS, configure shared data path, update preseed template rendering |

## Shared Profile Schema

See PIM's `docs/shared-profiles/README.md` for the full schema. PCS's Profile model declares the shared attributes plus PCS-specific ones:

**Shared** (same as PIM): `parent_id`, `hostname`, `username`, `password`, `fullname`, `timezone`, `domain`, `locale`, `keyboard`, `packages`, `authorized_keys_url`

**PCS-specific**: `interface`, `device`

PIM-specific attributes (`mirror_host`, `mirror_path`, `http_proxy`, etc.) are present in the YAML but silently ignored by PCS's model since it doesn't declare them.

## Coordination

This tier is coordinated with:
- `flat_record/docs/extensions/plan-04-per-model-data-paths.md` — prerequisite
- `pim/docs/shared-profiles/` — companion tier, should be executed first
