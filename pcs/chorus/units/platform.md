---
objective: "Operability — is the infrastructure pleasant and efficient to run?"
status: pending
---

# Platform Tier

**Objective:** Operability — is the infrastructure pleasant and efficient to run?

The Platform tier makes the Production-hardened infrastructure easy to observe, operate, and extend. It adds the tooling and polish that turns infrastructure into a platform that operators and tenants can depend on confidently.

## Applies to

All systems built on this stack: infrastructure, applications, and services.

## Planned work (not yet specified)

- **Observability:** Prometheus + Grafana for cluster, node, VM, and NAS metrics
- **Centralized logging:** Loki or similar, log shipping from all nodes and VMs
- **Tenant self-service:** PCS Rails app (tenant portal) — VM provisioning, resource usage, billing
- **CLI polish:** Rich status tables, progress indicators, `pcs status` unified dashboard
- **Runbooks:** Documented procedures for common operations and failure scenarios
- **Multi-cluster management:** `pcs` commands that operate across sites simultaneously
- **Service catalog:** Managed services (PostgreSQL, Redis, Rails) provisioned as opinionated VM profiles
- **Audit logging:** Record all `pcs` operations with operator identity and timestamp

## Plans will be added here when Production tier is complete and stable.
