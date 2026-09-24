# ADR-003: Data Model Reference for Cluster Formation Plans

**Status:** Accepted
**Date:** 2026-02-25
**Supersedes:** ADR-003 from `docs/foundation/`
**Applies to:** All cluster-formation tier plans and the provider/command code they describe

---

## Purpose

This ADR documents the actual state of the data models in the `pcs` gem as of the cluster formation plans. Plans reference specific model classes, methods, and field names. This document is the authoritative reference — if a plan contradicts this ADR, this ADR wins and the plan should be treated as having a typo.

Read this before implementing any cluster formation plan.

---

## Key Models and Their Roles

### `Pcs::Config` (`lib/pcs/config.rb`)

Loaded from `config/pcs.rb`. Global project config.

Relevant methods:
- `config.ssh_key_path` → `Pathname` to SSH private key
- `config.ssh_public_key` → String, contents of `.pub` file
- `config.defaults[:root_password]` → String

---

### `Pcs::Site` (`lib/pcs/models/site.rb`)

FlatRecord model. Per-site configuration loaded from `sites/{site}/`.

Relevant methods:
- `site.name` → String (site identifier)
- `site.domain` → String (DNS domain)

---

### `Pcs::Network` (`lib/pcs/models/network.rb`)

FlatRecord model. Network definitions loaded from site data.

Network keys are **`:compute`** and **`:storage`**.

Relevant methods:
- `network.name` → Symbol (`:compute` or `:storage`)
- `network.subnet` → String
- `network.gateway` → String

---

### `Pcs::Host` (`lib/pcs/models/host.rb`)

FlatRecord model with STI. Host entries loaded from site data.

Relevant methods:
- `host.hostname` → String
- `host.type` → String (e.g. `"pve"`, `"truenas"`, `"rpi"`, `"pikvm"`)
- `host.ip_on(:compute)` → String IP on compute/management network
- `host.ip_on(:storage)` → String IP on storage network (nil if not present)
- `host.fqdn` → String (`"#{hostname}.#{domain}"`)

STI subclasses in `lib/pcs/models/hosts/`:
- `Hosts::Pve` — Proxmox VE nodes
- `Hosts::Truenas` — TrueNAS NAS
- `Hosts::Pikvm` — PiKVM devices
- `Hosts::Rpi` — Raspberry Pi control plane

#### Host type strings

Host uses these type strings:
- `"pve"` — Proxmox VE node
- `"truenas"` — TrueNAS SCALE NAS
- `"pikvm"` — PiKVM
- `"rpi"` — Raspberry Pi (control plane)

Filter hosts by type: `Pcs::Host.where(type: "pve")` or iterate `Pcs::Host.all` and filter.

---

### `Pcs::Interface` (`lib/pcs/models/interface.rb`)

FlatRecord model. Per-host network interface assignments.

Relevant methods:
- `interface.host` → associated Host
- `interface.network` → associated Network
- `interface.ip` → String IP address

---

### `Pcs::State` (`lib/pcs/models/state.rb`)

Loaded from `states/{site}/state.yml`. Tracks operational progress.

**Host state:**
- `state.update_host(name, new_status, **attrs)`
- `state.host_status(name)` → current status string

**Service state:**
- `state.update_service(name, new_status, **attrs)` — `name` is a Symbol
- Pre-defined service keys: `:network`, `:cluster`, `:nas`
- `state.service_status(:cluster)` → current status string

**Always call `state.save!` after any mutation.**

---

## Provider Layer

Provider code lives under `lib/pcs/providers/`. Built by the cluster formation plans:

```
lib/pcs/providers/
  proxmox/
    cluster.rb      # Plan 01 — pvesh cluster operations
    storage.rb      # Plan 03 — pvesh storage registration + LVM
    router.rb       # Plan 04 — VyOS VM + VyOS config
    sdn.rb          # Plan 04 — Proxmox SDN zone
  truenas/
    provisioner.rb  # Plan 02 — midclt dataset/NFS/iSCSI
```

---

## SSH Pattern

All providers use the same SSH helper:

```ruby
def ssh(ip, &block)
  Adapters::SSH.connect(host: ip, key: config.ssh_key_path, user: "root", &block)
end
```

`ssh.exec!(cmd)` returns a String (stdout). It does NOT raise on non-zero exit code — the caller must check the output for error indicators or use a wrapper that checks exit codes.

For polling port availability:
```ruby
Adapters::SSH.port_open?(ip, port)
```

---

## Command Tree — What Exists vs What Needs to Be Added

### Exists
```
pcs new, pcs completions
pcs cp setup
pcs site add/remove/use/get/set
pcs host list/get/set
pcs service get/set/start/stop/restart/debug
pcs network list/scan
```

### Needs to be created (cluster formation plans)
```
pcs cluster create      # Plan 01
pcs cluster join        # Plan 01
pcs cluster token       # Plan 01
pcs cluster status      # Plan 01
pcs nas create          # Plan 02
pcs nas status          # Plan 02
pcs storage register    # Plan 03
pcs storage lvm-setup   # Plan 03
pcs storage status      # Plan 03
pcs router create       # Plan 04
pcs router configure    # Plan 04
pcs router status       # Plan 04
pcs sdn create          # Plan 04
```

Note: `pcs cluster install` already exists in `lib/pcs/commands/clusters_command.rb` (node provisioning — pre-existing, may need updating to align with new patterns).
