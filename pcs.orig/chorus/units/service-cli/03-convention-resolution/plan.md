---
---

# Plan 03 — Convention-Based Service Resolution

## Context

Read before starting:
- `lib/pcs/service.rb` — currently an empty module
- `lib/pcs/service/dnsmasq.rb` — `Service::Dnsmasq` class
- `lib/pcs/service/netboot.rb` — `Service::Netboot` class (renamed in plan-02)
- `lib/pcs/service/control_plane.rb` — `Service::ControlPlane` (not a managed service, used differently)
- `lib/pcs/commands/services_command.rb` — current command with case dispatch

## Background

Every service command (`Start`, `Stop`, `Restart`, `Debug`) duplicates a `case name when "dnsmasq" ... when "netboot"` dispatch block and a `KNOWN_SERVICES` constant. Since plan-02 aligned class names to CLI names (`Netboot` not `Netbootxyz`), we can resolve services by convention: `pcs service start netboot` -> `Pcs::Service::Netboot` via `const_get(name.capitalize)`.

## Implementation

### Step 1: Add resolution and discovery to `Pcs::Service`

Add `MANAGED`, `resolve`, `managed`, `managed_names` to the Service module.

### Step 2: Refactor ServicesCommand to use resolution

Replace the entire `ServicesCommand` with dispatch-free commands.

### Step 3: Remove all old dispatch artifacts

Delete all `KNOWN_SERVICES`, `SERVICE_CHECKS`, `SERVICE_MAP` constants and `case name when` blocks.

## Verification

```bash
bundle exec rspec
grep -rn "KNOWN_SERVICES\|SERVICE_CHECKS\|SERVICE_MAP" lib/
grep -rn "case name" lib/pcs/commands/services_command.rb
```

All greps empty. All specs green.
