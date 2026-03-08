---
---

# Plan 01 — Remove Tailscale and Cloudflare

## Context

Read before starting:
- `lib/pcs/services/tailscale_service.rb` — the file to delete
- `lib/pcs/commands/services_command.rb` — references TailscaleService in SERVICE_CHECKS, Start, Stop, Debug
- `lib/pcs/cli.rb` — requires tailscale_service
- `lib/pcs/templates/project/services.yml` — has tailscale entry
- `spec/fixtures/project/data/services.yml` — has tailscale entry
- `spec/fixtures/project/sites/sg/services.yml` — has tailscale instance
- `spec/fixtures/project/sites/rok/services.yml` — check for tailscale
- `CLAUDE.md` — documents four verticals, network provider, tunnel provider

## Implementation

### Step 1: Delete TailscaleService

Delete `lib/pcs/services/tailscale_service.rb`.

### Step 2: Remove tailscale from CLI requires

In `lib/pcs/cli.rb`, remove:
```ruby
require_relative "services/tailscale_service"
```

### Step 3: Remove tailscale from ServicesCommand

In `lib/pcs/commands/services_command.rb`:

- Remove `tailscale: Services::TailscaleService` from `SERVICE_CHECKS`
- Remove tailscale from `KNOWN_SERVICES` arrays in `Start` and `Stop`
- Remove the `when "tailscale"` case branches in `Start` and `Stop`
- Remove `"tailscale" => Services::TailscaleService` from `SERVICE_MAP` in `Debug`

### Step 4: Remove tailscale from fixture/template data

In `lib/pcs/templates/project/services.yml`, remove:
```yaml
- id: tailscale
  name: tailscale
```

In `spec/fixtures/project/data/services.yml`, remove the tailscale entry.

In `spec/fixtures/project/sites/sg/services.yml`, remove the tailscale entry.

Check `spec/fixtures/project/sites/rok/services.yml` — remove tailscale if present.

### Step 5: Remove cloudflare references

Search for any cloudflare references. Known locations:
- `CLAUDE.md` mentions cloudflare as tunnel provider and `config/cloudflare.yml`
- `lib/pcs/boot.rb` has `load_provider_config` which could load `config/cloudflare.yml`

Remove any cloudflare entries from templates or config references. The `load_provider_config` method can stay — it's generic and Proxmox still uses it.

### Step 6: Update CLAUDE.md

Update the "Four Verticals" section to **Two Verticals**:

| Vertical | Default Provider | Purpose |
|----------|-----------------|---------|
| `cluster` | Proxmox VE | Hypervisor cluster formation and management |
| `nas` | TrueNAS SCALE | Network-attached storage setup and management |

Remove all references to:
- `network` vertical / Tailscale provider
- `tunnel` vertical / Cloudflare provider
- `config/tailscale.yml` and `config/cloudflare.yml`
- `pcs network join/status` commands
- `providers/tailscale/` and `providers/cloudflare/` directories

Update the project structure to remove `config/tailscale.yml` and `config/cloudflare.yml`.

## Test Spec

### Verify removals
- `rspec` passes with no reference errors to TailscaleService
- `grep -r "tailscale" lib/ spec/` returns zero results (excluding this plan file)
- `grep -r "cloudflare" lib/ spec/` returns zero results
- `grep -r "tailscale\|cloudflare" CLAUDE.md` returns zero results

### Verify preserved functionality
- Existing service specs for dnsmasq and netboot still pass
- `ServicesCommand::Start` and `ServicesCommand::Stop` work for dnsmasq and netboot
- `ServicesCommand::Debug` works for dnsmasq and netboot

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
grep -r "tailscale" lib/ spec/
grep -r "cloudflare" lib/ spec/
```

All three greps should return empty. All specs green.
