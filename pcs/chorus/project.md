---
last_refreshed_at: "2026-02-27T00:00:00+08:00"
bootstrapped: true
---

# Project Context — PCS

PCS is a Ruby CLI gem for bootstrapping and managing bare-metal private cloud sites. It runs on a Raspberry Pi control plane to manage Proxmox clusters, TrueNAS storage, and PXE-based OS provisioning across physical sites. Built with dry-cli, FlatRecord (YAML persistence), and RestCli (resource command patterns).

See `CLAUDE.md` for conventions, design decisions, and implementation order.

## Architecture

```
CLI (dry-cli + RestCli::Registry)
  → Commands (one file per resource)
    → Models (FlatRecord::Base subclasses, YAML-backed)
    → Services (Dnsmasq, Netboot, ControlPlane)
    → Adapters (SSH, Nmap, Dnsmasq config, SystemCmd)
    → Providers (Proxmox::Installer)
    → Platform (Arch, Os — architecture/OS detection + installer URLs)
    → Views (RestCli::View subclasses with has_many associations)
```

### Boot Sequence

`Pcs.run(args)` → skips boot for `new`/`version` → `Pcs.boot!` → loads `pcs.rb` (project marker + DSL config) → configures FlatRecord → reloads models → dispatches to dry-cli.

Project detection walks up from CWD looking for `pcs.rb`. Site resolved from `PCS_SITE` env var or `.env` file.

## Models (FlatRecord)

All models inherit `FlatRecord::Base` with YAML backend. FlatRecord uses hierarchy mode — `Site` is the hierarchy parent, per-site data lives in `sites/<site_name>/`.

| Model | Source file | Associations | Notes |
|-------|------------|--------------|-------|
| `Site` | `sites/<name>/site.yml` | has_many hosts, networks, services | Hierarchy parent. `top_level_domain` class attribute. |
| `Host` | `sites/<site>/hosts.yml` | belongs_to site, has_many interfaces | STI via `type` column. Subclasses: PveHost, TruenasHost, PikvmHost, RpiHost. |
| `Network` | `sites/<site>/networks.yml` | belongs_to site, has_many interfaces | `primary` flag, `contains_ip?` helper. |
| `Interface` | `sites/<site>/interfaces.yml` | belongs_to host, belongs_to network | NIC-level: name, mac, ip. |
| `Role` | `data/roles.yml` | none | Read-only, non-hierarchical. Maps roles to host types + IP base octets. |
| `Profile` | shared `~/.local/share/provisioning/profiles.yml` | parent_id chain | Read-only, deep_merge. Parent chain inheritance for preseed data. |

## Command Tree

Project-scoped (inside `pcs.rb` project):
- `host {list,show,add,update,remove}` — CRUD for host inventory
- `network {list,show,add,update,remove}` — CRUD for network definitions
- `site {list,show,add,remove,use,update}` — site management + selection
- `console` — IRB session with models loaded

Linux-only (runs on RPi control plane):
- `network scan` — nmap scan of a network, creates/updates hosts + interfaces
- `service {list,show,start,stop,restart,reload,status}` — managed services (dnsmasq, netboot)
- `cluster install` — Proxmox installer via SSH
- `cp setup` — control plane initialization

Global:
- `new <name>` — scaffold a PCS project
- `version` — print version

## Services

Three internal service classes under `Pcs::Service::`. Not FlatRecord models — plain Ruby classes with class-level methods (`start`, `stop`, `reload`, `status`, `status_report`, `log_command`).

| Service | Runtime | Purpose |
|---------|---------|---------|
| `Dnsmasq` | systemd | PXE proxy DHCP on control plane |
| `Netboot` | Podman container | netboot.xyz + generated iPXE menus, preseeds, post-install scripts |
| `ControlPlane` | — | CP host setup (used by `cp setup`, not a managed service) |

Config via DSL: `Pcs.config.service.dnsmasq`, `Pcs.config.service.netboot`, `Pcs.config.service.proxmox`.

## Adapters

| Adapter | Purpose |
|---------|---------|
| `SSH` | net-ssh wrapper with `connect` and `probe` (credential guessing) |
| `Nmap` | Network scanning, XML output parsing |
| `Dnsmasq` | Config file generation for PXE proxy |
| `SystemCmd` | Shell command execution with sudo support, `file_write` |

## Config DSL

`pcs.rb` is the project marker and configuration file:

```ruby
Pcs.configure do |config|
  config.flat_record { |fr| fr.hierarchy model: "Pcs::Site", key: :name }
  config.networking { |net| net.dns_fallback_resolvers = [...] }
  config.service.dnsmasq { |dns| dns.proxy = true }
  config.service.netboot { |nb| nb.default_os = "debian-trixie" }
  config.service.proxmox { |px| px.default_preseed_interface = "enp1s0" }
  config.discovery { |d| d.users = %w[root admin] }
end
```

Settings classes: `FlatRecordSettings`, `NetworkingSettings`, `ServiceSettings` (nests `DnsmasqSettings`, `NetbootSettings`, `ProxmoxSettings`), `DiscoverySettings`.

## Templates

ERB templates in `lib/pcs/templates/`:
- `project/` — `pcs new` scaffold (pcs.rb, Gemfile, roles.yml, etc.)
- `netboot/` — iPXE menus, MAC boot scripts, preseed.cfg, post-install.sh
- `dnsmasq/` — PXE proxy config
- `pikvm/` — static network config
- `pve/` — Proxmox network interfaces
- `systemd/` — answer file HTTP service

## Platform

`Pcs::Platform` detects Darwin vs Linux, provides platform-specific network detection.

`Platform::Arch` — maps architectures to QEMU binaries, firmware paths, EFI settings.
`Platform::Os` — maps OS identifiers (e.g. `debian-trixie`) to installer kernel/initrd/firmware URLs.

## Test Structure

- `spec/pcs/models/` — model specs (host, site, network, interface, role, profile, config)
- `spec/pcs/commands/` — command structure spec
- `spec/pcs/views/` — view specs (hosts, sites)
- `spec/pcs/boot_spec.rb` — boot sequence spec
- `spec/e2e/` — Linux-only E2E tests (QEMU + bridge + PXE boot pipeline). Support classes: TestBridge, QemuLauncher, SshVerifier, TestProject.
- `spec/fixtures/project/` — fixture project with two sites (rok, sg)

## Dependencies

**Runtime**: dry-cli, tty-prompt, tty-table, tty-spinner, net-ssh, ed25519, bcrypt_pbkdf, faraday, faraday-retry, pastel, dotenv, ostruct, rexml, flat_record (local gem), rest_cli (local gem)

**Development**: rspec

## Development Status

11 units tracked in `chorus/units/`:

| Unit | Status | Plans |
|------|--------|-------|
| refactor | complete | 7 (FlatRecord migration, RestCli adoption, namespace cleanup, Host STI) |
| shared-profiles | complete | 1 (shared provisioning profiles) |
| simplification | complete | 9 (pcs.rb boot, config DSL, dissolve ProjectConfig/main.yml) |
| cleanup | complete | 4 (remove tailscale/cloudflare, dissolve Service model, service namespace) |
| service-cli | complete | 5 (config consolidation, convention resolution, reload verb, status) |
| e2e | complete | 5 (test harness, multi-arch QEMU, PXE handshake, full install) |
| networking | complete | 6 (Network/Interface models, scan redesign, view associations) |
| cluster-formation | pending | 4 (Proxmox cluster, NAS, storage integration, VyOS SDN) |
| operations | pending | 2 (Prometheus, Alertmanager) |
| platform | pending | 0 (observability, logging, tenant self-service — not yet specified) |
| production | pending | 0 (HA, backup, multi-site — not yet specified) |

**Current state**: Bootstrap pipeline is complete and tested end-to-end. The gem can scaffold projects, manage multi-site inventories (hosts, networks, interfaces), generate PXE boot infrastructure, and install Proxmox via preseed. Next phase is cluster formation (forming Proxmox clusters from installed nodes).
