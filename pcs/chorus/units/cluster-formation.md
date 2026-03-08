---
objective: "Correctness — turn independent, pre-provisioned infrastructure components into a functioning private cloud ready to accept tenant workloads."
status: pending
---

# Cluster Formation Tier

**Objective:** Correctness — turn independent, pre-provisioned infrastructure components into a functioning private cloud ready to accept tenant workloads.

**Starting point:** All PVE nodes installed with Proxmox VE, TrueNAS installed, network bridges and VLANs configured. Bootstrap and provisioning phases are complete.

**Ceiling:** A formed Proxmox cluster with shared storage, VyOS edge router, and Proxmox SDN — ready for an external tenant provisioning system to create workloads. PCS does not manage tenants.

## Read first

Before implementing any plan:

1. **`ADR-003-data-model-reference.md`** — authoritative reference for all model classes, method signatures, field names, and type strings. Plans may contain shorthand; this ADR is the source of truth.
2. **`ADR-001-ssh-cli-over-api-clients.md`** — why SSH+CLI (pvesh, midclt) not native API clients.
3. **`ADR-002-cluster-formation-scope.md`** — what is and is not in this tier's scope.

## Plans

| Plan | Target | Key Commands |
|------|--------|--------------|
| 01 | Proxmox cluster formation | `pcs cluster create/join/token/status` |
| 02 | TrueNAS NAS provisioning | `pcs nas create/status` |
| 03 | Storage integration | `pcs storage register/lvm-setup/status` |
| 04 | VyOS router + SDN | `pcs router create/configure/status`, `pcs sdn create` |

Plans 01 and 02 can run concurrently (no dependency between them).
Plan 03 depends on both 01 and 02.
Plan 04 depends on 03.

## Completion criteria

Cluster Formation is complete when:
- Proxmox cluster is quorate with all nodes
- TrueNAS storage is provisioned and registered in Proxmox
- VyOS VM is deployed and configured as edge router with NAT
- Proxmox SDN VLAN zone exists and is ready for VNet creation
- All commands are idempotent (safe to re-run)

Verification: create a test VM on `nas-vmdisks` storage, attach it to a manually-created VNet in `pcs-zone`, confirm it gets a DHCP address from VyOS and can reach the internet.

## What is NOT in this tier

- **Tenant provisioning** — separate project outside PCS. PCS provides the infrastructure; tenant lifecycle is managed elsewhere.
- **Observability** — Prometheus, Grafana, alerting. Planned as a separate "Operations" tier.
- **Resilience** — HA, VRRP, automated failover. Deferred to Production tier.
- **Multi-site** — federation, cross-site networking. Deferred.

## ADRs

| File | Topic |
|------|-------|
| `ADR-001-ssh-cli-over-api-clients.md` | Why SSH+CLI over native API clients |
| `ADR-002-cluster-formation-scope.md` | What is and is not in this tier's scope |
| `ADR-003-data-model-reference.md` | Model classes, methods, field names, type strings |
