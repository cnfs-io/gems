---
---

# Plan 01 — STI Interface Consistency

## Context — read these files first

- `lib/pcs/models/host.rb` — base class defines `render(output_dir)`, `deploy!(output_dir, state:)`, `configure!`, `healthy?`
- `lib/pcs/models/hosts/pve_host.rb` — conforms to base: `render(output_dir)`, `deploy!(output_dir, state:)`
- `lib/pcs/models/hosts/truenas_host.rb` — BROKEN: `render(output_dir, config:)`, `deploy!(output_dir, config:, state:)`, `configure!(config:)`, `healthy?` passes `config:` to `with_ssh`
- `lib/pcs/models/hosts/pikvm_host.rb` — BROKEN: same `config:` parameter issues as TrueNAS
- `lib/pcs/models/hosts/rpi_host.rb` — BROKEN: `render(output_dir, config:)`, `deploy!(output_dir, config:, state:)`, `configure!(config:)`
- `lib/pcs/providers/proxmox/installer.rb` — calls `host.rendered_interfaces`, accesses `host.site` directly (correct pattern)

## Overview

TruenasHost, PikvmHost, and RpiHost were written before the Config → Site refactor. They still accept a `config:` keyword argument that no longer exists in the architecture. The base Host class defines the strategy interface without `config:`, and PveHost (the most mature subclass) already follows the correct pattern — accessing site data via `host.site` association.

This plan normalizes all STI subclasses to match the base interface and PveHost's pattern.

## Implementation

### 1. Fix TruenasHost

Remove `config:` from all method signatures. Replace `config.ssh_public_key` with `site.ssh_public_key_content`. Replace any `config` references with `site` association access.

**Before:**
```ruby
def render(output_dir, config:)
  write_local(output_dir, "/root/.ssh/authorized_keys", config.ssh_public_key + "\n")
```

**After:**
```ruby
def render(output_dir)
  pub_key = site.ssh_public_key_content
  write_local(output_dir, "/root/.ssh/authorized_keys", pub_key + "\n") if pub_key
```

For `deploy!`: change `deploy!(output_dir, config:, state:)` → `deploy!(output_dir, state:)`. Replace `with_ssh_probe(config: config, state: state)` → `with_ssh_probe(state: state)`.

For `configure!`: change `configure!(config:)` → `configure!`. No body changes needed.

For `healthy?`: change `with_ssh(user: "root", config: Pcs::Config.load, state: Pcs::State.load)` → `with_ssh(user: "root", state: Pcs::State.load)`. (Note: `with_ssh` is defined on Host base and does NOT accept `config:`)

### 2. Fix PikvmHost

Same pattern as TrueNAS. Remove `config:` from `render`, `deploy!`, `configure!`.

**render:** Replace `config.ssh_public_key` with `site.ssh_public_key_content`.

**deploy!:** Change `with_ssh_probe(config: config, state: state)` → `with_ssh_probe(state: state)`.

**configure!:** Remove `config:` parameter.

**healthy?:** Change `with_ssh(user: "root", config: Pcs::Config.load, state: Pcs::State.load)` → `with_ssh(user: "root", state: Pcs::State.load)`.

### 3. Fix RpiHost

Remove `config:` from `render(output_dir, config:)` → `render(output_dir)`.
Remove `config:` from `deploy!(output_dir, config:, state:)` → `deploy!(output_dir, state:)`.
Remove `config:` from `configure!(config:)` → `configure!`.

RpiHost methods are mostly no-ops so the changes are just signature alignment.

### 4. Verify base class interface

Confirm the base Host class declares exactly these strategy methods:

```ruby
def render(output_dir)
def deploy!(output_dir, state:)
def configure!
def healthy?
```

All four STI subclasses must match these signatures exactly.

## Test Spec

No new specs needed — this is a signature fix. Run existing specs to confirm no regressions:

```
bundle exec rspec spec/pcs/models/host_spec.rb
bundle exec rspec spec/pcs/commands/command_structure_spec.rb
```

Verify that `TruenasHost.new`, `PikvmHost.new`, and `RpiHost.new` can be instantiated and their method signatures match the base class (the command_structure_spec already checks inheritance).

## Verification

- [ ] `grep -r "config:" lib/pcs/models/hosts/` returns zero matches
- [ ] `grep -rn "Config.load" lib/pcs/models/hosts/` returns zero matches
- [ ] All STI subclass methods have identical signatures to Host base class
- [ ] `bundle exec rspec` passes
