---
objective: "Extract profile data from PIM's project-scoped data directory to a shared XDG location."
status: complete
---

# Shared Profiles Tier — PIM

## Objective

Extract profile data from PIM's project-scoped data directory to a shared XDG location at `~/.local/share/provisioning/profiles.yml`. This establishes a canonical source of truth for machine provisioning profiles that both PIM and PCS can read from.

**The question this tier answers:** Can PIM read profiles from a shared location while keeping all other data project-scoped?

## Background

PIM and PCS both use profiles to drive preseed/autoinstall templates. The profile represents what a machine should look like: hostname, username, timezone, packages, SSH keys, etc. Today, profiles live inside each tool's project directory, meaning profile data is duplicated and can drift between tools.

By moving profiles to `~/.local/share/provisioning/profiles.yml`, both tools read from the same source. Each tool's Profile model declares the full attribute set (shared + tool-specific). FlatRecord silently ignores unknown attributes, so PIM can add fields PCS doesn't care about and vice versa.

## Shared Profile Schema

These attributes are used by both PIM and PCS preseed templates:

| Attribute | Type | Used by |
|-----------|------|---------|
| `parent_id` | string | Both (inheritance chain) |
| `hostname` | string | Both |
| `username` | string | Both |
| `password` | string | Both |
| `fullname` | string | Both |
| `timezone` | string | Both |
| `domain` | string | Both |
| `locale` | string | Both |
| `keyboard` | string | Both |
| `packages` | string | Both |
| `authorized_keys_url` | string | Both |

PIM-specific (PCS ignores):

| Attribute | Type |
|-----------|------|
| `mirror_host` | string |
| `mirror_path` | string |
| `http_proxy` | string |
| `partitioning_method` | string |
| `partitioning_recipe` | string |
| `tasksel` | string |
| `grub_device` | string |

PCS-specific (PIM ignores):

| Attribute | Type |
|-----------|------|
| `interface` | string |
| `device` | string |

Both models declare all attributes they need. Unknown attributes from the YAML file are silently ignored by ActiveModel.

## Key Design Decisions

- **Location**: `~/.local/share/provisioning/profiles.yml` — XDG-compliant, tool-agnostic
- **Single file**: One YAML file with all profiles, using FlatRecord collection layout
- **Read-only from projects**: Both tools treat shared profiles as read-only. Profile editing is done directly on the shared file (or via a future `provisioning` CLI tool)
- **Project profiles can override**: If a PIM or PCS project has a local `profiles.yml`, FlatRecord multi-path loading merges it over the shared data. This allows project-specific profile overrides while keeping shared defaults
- **No shared gem**: Both tools independently point at the same file. Schema alignment is by convention, not code dependency
- **Migration**: Existing PIM project profiles are copied to the shared location. PIM's data path for profiles is reconfigured

## Plans

| # | Name | Description |
|---|------|-------------|
| 01 | shared-profiles-pim | Reconfigure PIM to read profiles from shared XDG path, migrate existing data, update tests |

## Coordination

This tier has a companion in PCS: `docs/shared-profiles/`. Both should be executed independently — PIM first (since it has existing profile data to migrate), then PCS (which will be configured to read from the same path).

## File Layout After

```
~/.local/share/provisioning/
  profiles.yml                    # canonical shared profiles

~/my-pim-project/
  data/
    isos.yml                      # project-scoped (unchanged)
    builds.yml                    # project-scoped (unchanged)
    targets.yml                   # project-scoped (unchanged)
    profiles.yml                  # OPTIONAL: project-level overrides (merged over shared)
```

