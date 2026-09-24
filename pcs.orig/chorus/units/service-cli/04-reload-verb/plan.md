---
---

# Plan 04 — Add `reload` Verb

## Context

Read before starting:
- `lib/pcs/commands/services_command.rb` — refactored in plan-03, uses `with_service_context`
- `lib/pcs/service/netboot.rb` — already has `.reload(site:, system_cmd:)` method
- `lib/pcs/service/dnsmasq.rb` — already has `.reload(site:, system_cmd:)` method
- `lib/pcs/cli.rb` — CLI registry

## Background

Both `Service::Netboot` and `Service::Dnsmasq` already implement `.reload` at the service layer. Netboot's reload regenerates menus/preseeds/boot files without restarting the container. Dnsmasq's reload regenerates config and restarts the daemon (dnsmasq requires restart to re-read config — SIGHUP only re-reads hosts/leases). The only missing piece is the CLI command.

## Implementation

### Step 1: Add Reload command to ServicesCommand
### Step 2: Register in CLI
### Step 3: Verify `.reload` interface consistency

No changes needed to service classes.

## Verification

```bash
bundle exec rspec
# Manual: in a test project
pcs service reload netboot   # should regenerate files, not restart container
pcs service reload dnsmasq   # should regenerate config and restart dnsmasq
```
