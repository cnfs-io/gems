---
---

# Plan 04 — Host STI: Merge Device + Hosts into Pcs::Host

## Objective

Replace the separate `Pcs::Device` model and `Pcs::Hosts::*` strategy classes with a single `Pcs::Host` model using FlatRecord STI. Each host type becomes an STI subclass (`Pcs::PveHost`, `Pcs::TruenasHost`, `Pcs::PikvmHost`, `Pcs::RpiHost`) that carries both data attributes and behavior methods. The data file renames from `devices.yml` to `hosts.yml`.

## Context

Read before starting:
- `lib/pcs/models/device.rb` — current Device model (becomes Host base)
- `lib/pcs/hosts/base.rb` — current host strategy base class
- `lib/pcs/hosts/pve.rb` — PVE strategy (becomes PveHost)
- `lib/pcs/hosts/truenas.rb` — TrueNAS strategy (becomes TruenasHost)
- `lib/pcs/hosts/pikvm.rb` — PiKVM strategy (becomes PikvmHost)
- `lib/pcs/hosts/rpi.rb` — RPi strategy (becomes RpiHost)
- `lib/pcs/commands/devices_command.rb` — references Device (becomes HostsCommand)
- `lib/pcs/views/devices_view.rb` — references Device (becomes HostsView)

## Prerequisites

- Plan 03 (flatten namespace) must be complete — models are at `Pcs::Device`, not `Pcs::Models::Device`

## Key Design Decision: Site via Association, Not Parameter

FlatRecord's hierarchical mode automatically sets `site_id` on records. The `belongs_to :site` association on Host means `host.site` returns the Site record directly. Strategy methods do NOT need `site:` as a parameter.

## Implementation Spec

### Step 1: Create Host base model with STI

### Step 2: Create STI subclasses (PveHost, TruenasHost, PikvmHost, RpiHost)

### Step 3: Rename command, view, and CLI references (Device -> Host)

### Step 4: Update callers (Installer, CpCommand, ClustersCommand)

### Step 5: Data file rename (devices.yml -> hosts.yml)

### Step 6: Delete old files (Device model, Hosts:: strategies)

## Design Notes

- Site accessed via association, not parameter
- Use dot notation on Site, not `site.get(:field)`
- Only `config:` and `state:` remain as external params
- `Hosts::Base.strategy_for` is eliminated — FlatRecord STI handles dispatch
- No data migration for `type` column values
- Console ergonomics work naturally

## Verification

```bash
grep -r "Pcs::Hosts::\|Pcs::Device\b" lib/ spec/
# Should return empty

bundle exec rspec

pcs host list
pcs host show <id>
```
