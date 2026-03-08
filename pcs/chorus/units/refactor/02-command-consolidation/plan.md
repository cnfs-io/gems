---
---

# Plan 02 — Command Consolidation

## Objective

Restructure all PCS commands into the single-file-per-resource convention. Each resource gets one `*_command.rb` file with inner classes. Split `get` into `list` + `show`. Wire views into CRUD actions. Rewrite CLI registry.

## Context

Read before starting:
- `lib/pcs/cli.rb` — current CLI registry (will be rewritten)
- `lib/pcs/views/` — view files from plan 01
- All files in `lib/pcs/commands/` — current command implementations
- `lib/rest_cli/command.rb` — RestCli::Command base class

## Implementation Spec

### Strategy

For each resource, create a single `*_command.rb` file that:
1. Defines an outer class inheriting from `RestCli::Command`
2. Contains inner classes for each action, inheriting from `self`
3. CRUD actions (List, Show) use the view layer where practical
4. Action commands preserve their existing logic
5. Interactive TTY::Prompt commands move unchanged into inner classes

### Resource command files to create

See the full plan document for complete implementation specs of:
- `lib/pcs/commands/devices_command.rb`
- `lib/pcs/commands/services_command.rb`
- `lib/pcs/commands/sites_command.rb`
- `lib/pcs/commands/clusters_command.rb`
- `lib/pcs/commands/cp_command.rb`

### CLI Registry rewrite

Complete rewrite of `lib/pcs/cli.rb` with new command registrations.

### Command name changes

| Old | New |
|-----|-----|
| `device get` | `device list` / `device show` |
| `service get` | `service list` / `service show` |
| `site get` | `site list` / `site show` |

No backward compat aliases — clean break.

### Files to delete after consolidation

All old per-action files and their directories under `lib/pcs/commands/`.

## Verification

```bash
bundle exec rspec

# Manual smoke test
pcs version
pcs device list
pcs device show <id>
pcs service list
pcs site list
```
