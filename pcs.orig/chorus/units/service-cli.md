---
objective: "Make the pcs service command family production-ready: consolidate hardcoded values into the config DSL, eliminate case-dispatch boilerplate via convention-based service resolution, add missing lifecycle verbs."
status: complete
---

# Service CLI Tier — Service Command Improvements & Config Consolidation

## Objective

Make the `pcs service` command family production-ready: consolidate hardcoded values into the config DSL, eliminate case-dispatch boilerplate via convention-based service resolution, add missing lifecycle verbs (`reload`, `status` with `--follow`), and rename `Service::Netbootxyz` -> `Service::Netboot` so the class name matches the CLI name.

## Motivation

1. Operators testing PXE boot had to run `pcs service restart netboot` to regenerate menus/preseeds, which unnecessarily restarts the container. A `reload` verb is needed.
2. The `debug` command name misleads — it's a health dashboard, not a log viewer. Rename to `status` and add `--follow`/`--lines` flags for log tailing.
3. Hardcoded paths and timeouts are scattered across service classes, adapters, and providers. All should live in `pcs.rb` via the config DSL.
4. Every service command duplicates a `case name when ... end` dispatch block and `KNOWN_SERVICES` constant. Convention-based resolution (`const_get`) eliminates this entirely.

## Plan Table

| Plan | Name | Description | Depends On |
|------|------|-------------|------------|
| 01 | config-consolidation | Move hardcoded values into Config DSL with sensible defaults | — |
| 02 | rename-netboot | Rename `Service::Netbootxyz` -> `Service::Netboot`, update all references | 01 |
| 03 | convention-resolution | Replace case dispatch with `Service.const_get(name.capitalize)`, add `Service.all` | 02 |
| 04 | reload-verb | Add `reload` to ServicesCommand, wire to `.reload` on each service class | 03 |
| 05 | status-and-logs | Rename `debug` -> `status`, add `--follow`/`--lines` flags for log tailing | 03 |

## Completion Criteria

- [ ] `pcs service reload netboot` regenerates menus/preseeds without restarting the container
- [ ] `pcs service reload dnsmasq` regenerates config and restarts dnsmasq (no way around it)
- [ ] `pcs service status netboot` shows health dashboard + recent logs
- [ ] `pcs service status netboot --follow` tails container logs live
- [ ] `pcs service status dnsmasq --follow` tails journalctl live
- [ ] No `case name when` dispatch in any service command
- [ ] No `KNOWN_SERVICES` or `SERVICE_CHECKS` constants
- [ ] No `DEFAULT_*` constants or class-level accessors for paths in service classes
- [ ] All hardcoded values accessible via `Pcs.config.*` with documented defaults
- [ ] All existing specs pass
- [ ] `Service::Netbootxyz` no longer exists (renamed to `Service::Netboot`)
