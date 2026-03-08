---
---

# Plan 05 — Rename `debug` -> `status` with Log Tailing

## Context

Read before starting:
- `lib/pcs/commands/services_command.rb` — `Debug` command class (after plan-03 refactor)
- `lib/pcs/service/netboot.rb` — `.debug(system_cmd:, pastel:)` method
- `lib/pcs/service/dnsmasq.rb` — `.debug(system_cmd:, pastel:)` method
- `lib/pcs/cli.rb` — CLI registry

## Background

The `debug` command is actually a health dashboard: container status, port checks, file inventory, config summary, and a snippet of recent logs. The name `debug` misleads operators into expecting verbose log output. Renaming to `status` aligns with systemd conventions (`systemctl status <unit>`) and sets the right expectation.

Additionally, the current command only shows historical log output (last N lines). Operators troubleshooting PXE boot need to tail logs in real-time. Adding `--follow` and `--lines` flags makes `status` the single observability entry point — a quick health check by default, a live log stream with `--follow`.

## Implementation

### Step 1: Rename `.debug` -> `.status_report` on service classes
### Step 2: Replace Debug command with Status command (with `--follow` and `--lines` flags)
### Step 3: Update the status_report methods to use `--lines`
### Step 4: Update CLI registry
### Step 5: Handle tail_logs via service interface (add `.log_command` class method)

## Verification

```bash
bundle exec rspec
grep -rn "\.debug\b" lib/pcs/commands/
grep -rn "class Debug" lib/pcs/commands/
grep -rn "service debug" lib/pcs/cli.rb
```

All greps empty. All specs green.

Manual test:
```bash
pcs service status netboot           # health dashboard + 20 recent log lines
pcs service status netboot -n 100    # health dashboard + 100 recent log lines
pcs service status netboot -f        # tails podman logs (Ctrl+C to exit)
pcs service status dnsmasq -f        # tails journalctl (Ctrl+C to exit)
```
