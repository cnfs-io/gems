---
---

# Plan 07 — Host Class Defaults

## Objective

Add class-level defaults to Host STI subclasses (starting with `PveHost`). Move `preseed_interface` and `preseed_device` from `ProjectConfig.defaults` to `PveHost.default_preseed_interface` and `PveHost.default_preseed_device`. These are set by the user in `pcs.rb` and used as pre-fill values when creating/configuring hosts.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pcs/lib/pcs/models/hosts/pve_host.rb` — PveHost STI subclass
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/host.rb` — Host base class
- `~/.local/share/ppm/gems/pcs/lib/pcs/models/config.rb` — `ProjectConfig`: `defaults[:preseed_interface]`, etc.
- `~/.local/share/ppm/gems/pcs/lib/pcs/services/netboot_service.rb` — `generate_preseed_files`

## Design

`class_attribute` from ActiveSupport provides inheritable class-level defaults. Each STI subclass can have its own defaults. Instance attributes populated from class defaults on initialize via `after_initialize`.

## Implementation

### 1. Add `preseed_device` attribute to Host
### 2. Update PveHost with class_attributes and after_initialize
### 3. Update `NetbootService.generate_preseed_files`
### 4. Update `HostsCommand::Set` interactive mode
### 5. Update pcs.rb template

## Verification

1. `bundle exec rspec` — all green
2. `Pcs::PveHost.default_preseed_interface` returns sensible default
3. New PveHost instances get the class default
