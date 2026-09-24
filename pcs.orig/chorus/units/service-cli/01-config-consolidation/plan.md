---
---

# Plan 01 — Config Consolidation

## Context

Read before starting:
- `lib/pcs/config.rb` — current Config DSL with `NetbootxyzSettings`, `DnsmasqSettings`, `ServiceSettings`
- `lib/pcs/service/netbootxyz.rb` — `DEFAULT_NETBOOT_DIR`, class-level `netboot_dir` accessor
- `lib/pcs/adapters/dnsmasq.rb` — hardcoded `/etc/dnsmasq.d/` path
- `lib/pcs/models/hosts/pve_host.rb` — `default_preseed_interface`, `default_preseed_device` as class_attributes
- `lib/pcs/providers/proxmox/installer.rb` — `REBOOT_INITIAL_WAIT`, `REBOOT_POLL_INTERVAL`, `REBOOT_MAX_ATTEMPTS`, `PVE_WEB_PORT` constants
- `lib/pcs/adapters/ssh.rb` — hardcoded discovery users/passwords in `probe` method
- `lib/pcs/templates/project/pcs.rb.erb` — project scaffold template
- `spec/fixtures/project/pcs.rb` — test fixture config

## Background

Hardcoded values are scattered across service classes, adapters, models, and providers. Some use constants, some use class_attributes, some are inline literals. This plan consolidates them all into the Config DSL so operators have a single place (`pcs.rb`) to tune behavior.

## Implementation

### Step 1: Add `netboot_dir` to `NetbootxyzSettings`
### Step 2: Add `config_dir` to `DnsmasqSettings`
### Step 3: Add `ProxmoxSettings` for PVE defaults and installer timeouts
### Step 4: Add `DiscoverySettings` for SSH probe credentials
### Step 5: Update project scaffold template
### Step 6: Update test fixture

## Verification

```bash
bundle exec rspec
grep -rn "DEFAULT_NETBOOT_DIR\|KNOWN_SERVICES\|SERVICE_CHECKS" lib/
grep -rn "REBOOT_INITIAL_WAIT\|REBOOT_POLL_INTERVAL\|REBOOT_MAX_ATTEMPTS\|PVE_WEB_PORT" lib/pcs/providers/
```

All greps empty. All specs green.
