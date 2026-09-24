---
objective: "Remove tailscale and cloudflare from PCS scope. Remove the Service FlatRecord model and replace it with internal service classes under Pcs::Service::. Dnsmasq and netbootxyz become gem infrastructure."
status: complete
---

# Cleanup Tier — PCS

## Objective

Remove tailscale and cloudflare from PCS scope. Remove the `Service` FlatRecord model and replace it with internal service classes under `Pcs::Service::`. Dnsmasq and netbootxyz become gem infrastructure — hardcoded bootstrap dependencies, not user-configurable services.

**The question this tier answers:** Can PCS manage its two bootstrap services (dnsmasq, netbootxyz) as internal infrastructure without a generic Service model or the overhead of per-site YAML state files?

## Background

PCS originally defined four verticals: cluster (Proxmox), nas (TrueNAS), network (Tailscale), tunnel (Cloudflare). Architectural review determined:

- **Tailscale** — inter-site mesh networking is a cross-site concern, not site-scoped. Container labeling is L3 (tenant workloads). Device enrollment will be done manually until the tool is better understood. Remove from PCS entirely.
- **Cloudflare Tunnel** — operational concern (exposing running services), not bootstrap. Remove from PCS entirely.
- **Service model** — over-engineering for two bootstrap services. The parent-chain inheritance, per-site YAML state, `data/services.yml` definitions, and `ServicesCommand` CRUD are unnecessary when the only consumers are dnsmasq and netbootxyz — both of which require gem code to function. No user-added service would work without writing Ruby.

After this tier, PCS has **two verticals**: cluster (Proxmox) and nas (TrueNAS). Dnsmasq and netbootxyz are internal service classes called by bootstrap commands.

## Plans

| # | Name | Description | Depends On |
|---|------|-------------|------------|
| 01 | remove-tailscale-cloudflare | Delete TailscaleService, all tailscale/cloudflare references, config files, fixture data | — |
| 02 | dissolve-service-model | Delete Service FlatRecord model, services.yml files, ServicesView, ServicesCommand. Inline config into Pcs::Config DSL | plan-01 |
| 03 | service-namespace | Rename DnsmasqService → Pcs::Service::Dnsmasq, NetbootService → Pcs::Service::Netbootxyz. Move from services/ to service/. Update CLI registration | plan-02 |
| 04 | netboot-platform-only | Remove Service.definition fallback from NetbootService. Use Platform::Os exclusively for kernel/initrd URLs. Clean up download_boot_files | plan-03 |

## Key Decisions

- **Naming**: `Pcs::Service::Dnsmasq` and `Pcs::Service::Netbootxyz` — "Service" accurately describes lifecycle management (start/stop/status/debug). The old Service *model* goes away, so no naming collision.
- **Config DSL**: `config.service.dnsmasq` and `config.service.netbootxyz` blocks in `pcs.rb` replace `data/services.yml`. Only operational config (image name, proxy mode, ipxe timeout) — no kernel/initrd URLs (those come from `Platform::Os`).
- **ControlPlaneService**: Stays as-is — it's already a plain Ruby class, not model-backed. Rename to `Pcs::Service::ControlPlane` for consistency in plan-03.
- **Command tree**: `pcs service {start,stop,restart,debug}` commands stay but are simplified — hardcoded to dnsmasq/netbootxyz, no CRUD, no model lookups.
- **No services.yml anywhere**: Neither `data/services.yml` (project-wide definitions) nor `sites/<site>/services.yml` (per-site state). Service status is always live-checked via systemctl/podman.

## Files Removed

```
lib/pcs/models/service.rb
lib/pcs/services/tailscale_service.rb
lib/pcs/views/services_view.rb
lib/pcs/templates/project/services.yml      (the data/services.yml template)
spec/pcs/models/services_spec.rb
spec/pcs/views/services_view_spec.rb
spec/fixtures/project/data/services.yml
spec/fixtures/project/sites/rok/services.yml
spec/fixtures/project/sites/sg/services.yml
config/tailscale.yml                        (from project template, if present)
```

## Files Created

```
lib/pcs/service/dnsmasq.rb                  (moved from services/dnsmasq_service.rb)
lib/pcs/service/netbootxyz.rb               (moved from services/netboot_service.rb)
lib/pcs/service/control_plane.rb            (moved from services/control_plane_service.rb)
```

## Project Layout After Completion

```
lib/pcs/
  service/
    dnsmasq.rb                   # Pcs::Service::Dnsmasq
    netbootxyz.rb                # Pcs::Service::Netbootxyz
    control_plane.rb             # Pcs::Service::ControlPlane
  # services/ directory removed
  # models/service.rb removed
```

Config in `pcs.rb`:
```ruby
Pcs.configure do |config|
  config.service.dnsmasq do |dns|
    dns.proxy = true
  end

  config.service.netbootxyz do |nb|
    nb.image = "docker.io/netbootxyz/netbootxyz"
    nb.ipxe_timeout = 10
  end
end
```

## Completion Criteria

- No references to tailscale or cloudflare anywhere in the gem
- No `Pcs::Service` FlatRecord model or `services.yml` files
- `Pcs::Service::Dnsmasq`, `Pcs::Service::Netbootxyz`, `Pcs::Service::ControlPlane` exist
- `config.service.dnsmasq` and `config.service.netbootxyz` DSL blocks work
- NetbootService uses `Platform::Os` exclusively for kernel/initrd URLs — no Service.definition fallback
- `pcs service start dnsmasq`, `pcs service debug netboot` etc. still work
- CLAUDE.md updated: two verticals (cluster, nas), no network/tunnel references
- All specs pass
