---
objective: "Bring PIM's CLI registration in cli.rb into conformance with the conventions established in PCS."
status: complete
---

# CLI Conventions — Align PIM CLI with PCS Patterns

## Objective

Bring PIM's CLI registration in `cli.rb` into conformance with the conventions established in PCS. This is a cleanup tier — no new functionality, just consistency.

## Conventions (from PCS)

PCS uses RestCli's `aliases:` keyword on the primary command to register short forms:

```ruby
register "host list",   HostsCommand::List, aliases: ["ls"]
register "host show",   HostsCommand::Show
register "host add",    HostsCommand::Add, aliases: ["a"]
register "host update", HostsCommand::Update
register "host remove", HostsCommand::Remove, aliases: ["rm"]
```

Key conventions:
1. **`list`** is the primary verb; `ls` is an alias via `aliases: ["ls"]` — NOT a separate registration
2. **`show`** is the verb for viewing a single record — NOT `get`
3. **`update`** is the verb for modifying — NOT `set` (note: config is an exception, see below)
4. **`add`** and **`remove`** (alias `rm`) for CRUD on resource command sets that support it
5. **No duplicate registrations** — aliases are handled by the `aliases:` keyword

## What Needs to Change in PIM

### cli.rb registration cleanup

| Command set | Current problems | Target state |
|-------------|-----------------|--------------|
| profile | `ls` is separate registration; `get` alias for show; missing `remove` | `list` with `aliases: ["ls"]`; drop `get`; add `remove` |
| iso | `ls` is separate registration; `get` alias for show; missing `remove` | `list` with `aliases: ["ls"]`; drop `get`; add `remove` |
| build | `ls` is separate registration; `get` alias for show | `list` with `aliases: ["ls"]`; drop `get` |
| target | `ls` is separate registration; `get` alias for show; missing `add`, `remove` | `list` with `aliases: ["ls"]`; drop `get`; add `add`, `remove` |
| ventoy | No `list`/`ls` issues; `config` should be `show` | Rename `config` → `show` |
| config | `ls` is separate registration; has `get`/`set` | `list` with `aliases: ["ls"]`; `get`/`set` are fine for config (it's key-value, not a resource) |

### Missing commands to stub

For resource sets (profile, iso, target), we need `add` and `remove` stubs where missing. Builds are a special case — you don't manually add/remove build recipes through CLI, you edit YAML files, so builds only need list/show/run/clean/status/verify.

### Ventoy is not a resource set

Ventoy is operational (prepare/copy/status/download) plus a `show` for config. It doesn't follow the list/show/add/remove pattern.

## Plan Table

| # | Plan | Description |
|---|------|-------------|
| 01 | cli-registration-cleanup | Fix all registrations in cli.rb, add stub commands |

## Completion Criteria

- [ ] `pim profile ls` works (via alias, not separate registration)
- [ ] `pim profile get` is removed (use `show`)
- [ ] `pim iso get` is removed (use `show`)
- [ ] `pim build get` is removed (use `show`)
- [ ] `pim target get` is removed (use `show`)
- [ ] `pim profile remove` exists (stub)
- [ ] `pim iso remove` exists (stub)
- [ ] `pim target add` exists (stub)
- [ ] `pim target remove` exists (stub)
- [ ] `pim ventoy config` renamed to `pim ventoy show`
- [ ] `pim config ls` works via alias
- [ ] No duplicate command registrations in cli.rb
- [ ] All existing specs pass

