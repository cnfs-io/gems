---
---

# Plan 02 — Dead Code Removal

## Context — read these files first

- `netboot/` (project root) — Jinja2 templates: `ipxe_menu.j2`, `post_install.sh.j2`, `preseed.cfg.j2`
- `lib/pcs/templates/netboot/` — Current ERB templates that replaced the Jinja2 versions
- `spec/fixtures/project/sites/main.yml` — Legacy config structure not read by any code
- `notes.txt` (project root) — Check if still relevant
- `lib/pcs/adapters/ssh.rb` — `detect_type` method references nonexistent constants
- `lib/pcs/models/host.rb` — `compute_ip` and `storage_ip` attributes are vestigial

## Overview

Several files and code paths are left over from earlier iterations. They're not causing failures (nothing references them), but they add confusion for anyone reading the codebase. Clean them out.

## Implementation

### 1. Remove `netboot/` directory at project root

These are Jinja2 (`.j2`) templates from the pre-Ruby era. The current ERB templates in `lib/pcs/templates/netboot/` have replaced them entirely.

```
rm -rf netboot/
```

### 2. Remove `spec/fixtures/project/sites/main.yml`

This file contains a legacy structure (`defaults`, `sites`, `devices`, `ip_assignments`) that nothing in the current codebase reads. The current architecture uses:
- `data/roles.yml` for role→type mappings and IP base octets
- Per-site `site.yml` for site-level config
- `pcs.rb` DSL for project config

Remove `spec/fixtures/project/sites/main.yml`. Run specs to confirm nothing breaks.

### 3. Remove `notes.txt` at project root

Read first to check if anything is actionable. If it's just scratch notes, remove it.

### 4. Fix `SSH.detect_type` constant references

In `lib/pcs/adapters/ssh.rb`, the `detect_type` method references:
- `Hosts::PVE` → should be `Pcs::PveHost`
- `Hosts::TrueNAS` → should be `Pcs::TruenasHost`
- `Hosts::PiKVM` → should be `Pcs::PikvmHost`
- `Hosts::RPi` → should be `Pcs::RpiHost`

Fix all four constant references. This method would currently raise `NameError` if called.

### 5. Remove vestigial `compute_ip` and `storage_ip` attributes from Host

The Host model declares `attribute :compute_ip, :string` and `attribute :storage_ip, :string`, but IPs now live on Interface records. These attributes are still in the host fixture data (host id=6 has `compute_ip: 172.31.1.41` and `storage_ip: 172.31.2.41`), but the actual source of truth is the Interface model.

**Action:**
- Remove `attribute :compute_ip` and `attribute :storage_ip` from `lib/pcs/models/host.rb`
- Remove `compute_ip` and `storage_ip` keys from fixture files: `spec/fixtures/project/sites/sg/hosts.yml`
- Remove `:compute_ip` and `:storage_ip` from `FIELDS` and `MUTABLE_FIELDS` constants
- Check `HostsCommand::Update#interactive_configure` — it prompts for `compute_ip` and passes it to `host.update`. This needs to be changed to create/update an Interface instead, or removed from the interactive flow (creating an Interface is more appropriate for a separate command)
- For now, **remove** the `compute_ip` prompt from `interactive_configure`. The correct flow is: configure host metadata (role, type, hostname, arch) via `host update`, then manage IPs via Interface records (which already happen through `network scan` or could be added via a future `interface add` command).

**Update fixture data:**
- Remove `compute_ip` and `storage_ip` from `spec/fixtures/project/sites/sg/hosts.yml`

## Test Spec

No new specs. Run full suite to confirm no regressions:

```
bundle exec rspec
```

The existing "no old references" specs in `command_structure_spec.rb` will help catch any remaining stale references.

## Verification

- [ ] `netboot/` directory at project root does not exist
- [ ] `spec/fixtures/project/sites/main.yml` does not exist
- [ ] `notes.txt` does not exist (or justified if kept)
- [ ] `grep -n "Hosts::" lib/pcs/adapters/ssh.rb` returns zero matches
- [ ] `grep -n "compute_ip\|storage_ip" lib/pcs/models/host.rb` returns zero matches
- [ ] `grep -n "compute_ip\|storage_ip" spec/fixtures/project/sites/sg/hosts.yml` returns zero matches
- [ ] `bundle exec rspec` passes
