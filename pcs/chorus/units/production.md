---
objective: "Resilience — does the infrastructure keep working when things go wrong?"
status: pending
---

# Production Tier

**Objective:** Resilience — does the infrastructure keep working when things go wrong?

The Production tier hardens the Foundation. It adds fault tolerance, redundancy, and automated recovery so that single component failures do not cause outages.

## Applies to

All systems built on this stack: infrastructure, applications, and services.

## Planned work (not yet specified)

- **Proxmox HA:** HA manager, softdog/IPMI watchdog, HA groups, per-VM HA policies
- **VyOS HA:** Active/passive VRRP with a second VyOS VM, automatic failover
- **Backup automation:** Proxmox Backup Server (PBS) or NAS-based scheduled backups with retention policies
- **Multi-site:** Cluster federation across Singapore, Rochester, Asheville sites
- **Storage redundancy:** TrueNAS ZFS RAIDZ, replication to second site
- **Network redundancy:** Bonded NICs on cluster nodes

## Plans will be added here when Foundation is complete and stable.
