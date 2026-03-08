# ADR-002: Cluster Formation Tier Scope

**Status:** Accepted
**Date:** 2026-02-25
**Supersedes:** ADR-002 (Foundation Scope) from `docs/foundation/`
**Applies to:** All cluster-formation tier plans

---

## Context

The `pcs` gem manages the L2 (cloud provider) layer of a private cloud stack. Development is organized across three maturity tiers:

| Tier | Directory | Objective |
|------|-----------|-----------|
| **Cluster Formation** | `docs/cluster-formation/` | Correctness — does the cloud infrastructure come up correctly? |
| **Production** | `docs/production/` | Resilience — does it keep working when things go wrong? |
| **Platform** | `docs/platform/` | Operability — is it pleasant and efficient to run? |

This ADR defines what is and is not in scope for the Cluster Formation tier.

---

## Prerequisites (already complete)

The following are **not part of this tier** — they are prerequisites that have already been completed:

- PVE node provisioning (Debian → Proxmox VE installation)
- TrueNAS SCALE installation
- Network bridge configuration on PVE nodes (vmbr0, storage bridges)
- VLAN configuration at the physical/L1 layer
- Host discovery, IP assignment, and SSH key deployment
- PCS project scaffolding, site configuration, IPAM population

---

## Cluster Formation Tier: In Scope

### Infrastructure
- Proxmox VE cluster formation (create, join, quorum verification)
- Proxmox API token creation for automation
- TrueNAS dataset, NFS share, and iSCSI target provisioning via `midclt`
- NFS and iSCSI storage registration in Proxmox
- LVM-thin pool creation on shared iSCSI LUN
- Single VyOS VM as cluster edge router (no HA)
- VyOS base configuration: WAN, NAT, firewall, DHCP server capability
- Proxmox SDN: VLAN zone creation, ready for VNet provisioning

### `pcs` gem commands
- `pcs cluster create` — form cluster on first node
- `pcs cluster join` — join additional nodes
- `pcs cluster token` — create automation API token
- `pcs cluster status` — cluster health and membership
- `pcs nas create` — provision TrueNAS datasets, NFS, iSCSI
- `pcs nas status` — NAS health
- `pcs storage register` — register NAS storage in Proxmox
- `pcs storage lvm-setup` — create LVM-thin pool on iSCSI LUN
- `pcs storage status` — verify storage visibility across cluster
- `pcs router create` — deploy VyOS VM
- `pcs router configure` — configure VyOS networking and services
- `pcs router status` — VyOS health
- `pcs sdn create` — configure Proxmox SDN VLAN zone

---

## Cluster Formation Tier: Explicitly Out of Scope

### Tenant provisioning (→ separate project)
- Tenant creation, VLAN allocation, resource pool management
- Per-tenant VNet creation in Proxmox SDN
- Per-tenant DHCP/routing on VyOS
- Tenant lifecycle management

PCS provides the infrastructure platform. Tenant provisioning is a separate concern managed by a different tool. PCS's ceiling is: "the cloud is ready to accept tenants."

### Observability (→ Operations tier)
- Prometheus, node-exporter, metrics collection
- Grafana dashboards
- Alerting and notifications (Alertmanager, Telegram, email)
- Centralized logging

### Resilience (→ Production tier)
- Proxmox HA manager and watchdog
- VyOS active/passive VRRP (redundant routers)
- Multi-site cluster federation
- Backup automation and retention policies
- Automated failure detection and recovery

### Operability (→ Platform tier)
- CLI UX polish (progress bars, rich status tables)
- Runbooks and operational documentation
- Multi-cluster management

---

## Consequences

This scope boundary means:

- A single node failure requires manual intervention — acceptable for this tier
- VyOS VM failure requires manual restart — acceptable for this tier
- No automated backups — operator's responsibility until Production tier
- Tenant creation requires a separate tool — PCS only builds the platform
- No metrics or alerting — operator monitors manually until Operations tier

Any implementation that adds Production, Platform, Operations, or Tenant features to Cluster Formation plans should be rejected and deferred to the appropriate tier or project.
