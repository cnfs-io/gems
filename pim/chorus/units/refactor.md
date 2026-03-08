---
objective: "Refactor PIM's command and view layers to adopt the rest_cli framework conventions."
status: complete
---

# Refactor Tier — PIM RestCli Adoption

## Objective

Refactor PIM's command and view layers to adopt the rest_cli framework conventions. After this tier, all resource commands use the `RestCli::Command` base class with inner-class-per-action pattern, all FlatRecord-backed resources have proper views, and duplicated hand-rolled rendering code is eliminated.

**The question this tier answers:** Can PIM adopt rest_cli conventions cleanly while preserving its domain-specific action commands?

## Key Design Decisions

- **One file per resource** — all inner classes (CRUD and action) in a single `*_command.rb` file
- **Outer class inherits from `RestCli::Command`** — inner classes use `< self`
- **Action commands coexist with CRUD commands** — `builds_command.rb` has List, Show (CRUD) alongside Run, Clean, Status (actions). Action inner classes simply don't use the view layer.
- **Standalone commands stay separate** — `new.rb`, `console.rb`, `serve.rb`, `version.rb` remain as individual files inheriting from `Dry::CLI::Command` directly
- **Verify is a build action** — `verify` moves into `BuildsCommand::Verify` since it operates on build recipes. Top-level `pim verify` alias preserved for backward compatibility.
- **`Pim.configure_flat_record!` moves to boot** — called once during app startup, removed from individual commands
- **Config commands are non-model** — `ConfigCommand` uses the same file convention but inner classes have custom implementations (no FlatRecord model backing them)

## Completion Criteria

- [ ] `RestCli::Base` → `RestCli::View` reference updated in ProfilesView
- [ ] Views exist for all FlatRecord models: Profile, Iso, Build, Target
- [ ] All resource commands consolidated into single-file convention (`*_command.rb`)
- [ ] All hand-rolled list/show rendering replaced with view calls
- [ ] `Pim.configure_flat_record!` called at boot, removed from commands
- [ ] Standalone commands untouched (new, console, serve, version)
- [ ] `verify` command consolidated into `BuildsCommand::Verify` with top-level alias
- [ ] CLI registry updated for new command class paths
- [ ] All existing specs pass (or are updated for new paths)
- [ ] Manual smoke test: all `pim` commands work as before

## Plans

| # | Name | Description |
|---|------|-------------|
| 01 | view-rename-and-boot | Update RestCli::Base→View, centralize flat_record boot |
| 02 | resource-views | Create IsoView, BuildsView, TargetsView with columns/detail_fields |
| 03 | command-consolidation | Restructure all commands into single-file-per-resource convention, update CLI registry |

## File Layout After Refactor

```
lib/pim/
  commands/
    profiles_command.rb      # List, Show, Add
    isos_command.rb          # List, Show, Add, Download, Verify
    builds_command.rb        # List, Show, Run, Clean, Status
    targets_command.rb       # List, Show
    ventoy_command.rb        # Prepare, Copy, Status, Config, Download
    config_command.rb        # List, Get, Set
    new.rb                   # standalone
    console.rb               # standalone
    serve.rb                 # standalone
    verify.rb                # standalone
    version.rb               # standalone
  views/
    profiles_view.rb         # existing, updated
    isos_view.rb             # new
    builds_view.rb           # new
    targets_view.rb          # new
  models/                    # unchanged
    build.rb
    iso.rb
    profile.rb
    target.rb
    targets/
      aws.rb
      iso_target.rb
      local.rb
      proxmox.rb
```

## Risk

The CLI registry aliases (`ls` → `get`, `c` → `console`) must be preserved. The refactor changes command class paths but the user-facing command names stay the same.

