---
objective: "Visibility — deploy a standard observability stack on the PCS control plane, enable exporters on all managed hosts, configure alerting, and verify the full pipeline end-to-end."
status: pending
---

# Operations Tier

**Objective:** Visibility — can I see what's happening across the cluster?

Deploy a standard observability stack on the PCS control plane (RPi), enable exporters on all managed hosts, configure alerting, and verify the full pipeline end-to-end.

**Starting point:** Cluster Formation tier complete — Proxmox cluster quorate, TrueNAS storage integrated, VyOS routing, SDN zone ready.

**Ceiling:** Prometheus scraping all infrastructure components, Grafana dashboards accessible, alerts firing to Google Chat/webhooks when things go wrong. The operator can see cluster health at a glance and gets notified of problems without polling manually.

## Design Principles

### Observability as control plane services

Prometheus, Alertmanager, and Grafana follow the same pattern as dnsmasq and netboot — they are Podman containers on the RPi managed via `pcs service start/stop/reload/status`. Configuration is generated from the site's host and network data, not hand-written.

This means the monitoring stack survives cluster failures. If all PVE nodes go down, the control plane still has the last-known metrics, can still fire alerts, and Grafana is still accessible for diagnosis.

### Config is derived, not manual

Just as dnsmasq config is generated from IPAM data, Prometheus scrape targets are generated from the host model. PCS knows every PVE node, the NAS, and VyOS — it generates `prometheus.yml` with all the right targets. Alertmanager routing is generated from notification config in `config/pcs.rb`. Adding a new node to IPAM and running `pcs service reload prometheus` is all it takes.

### Verification is a first-class step

Each plan includes concrete verification: metrics flowing, dashboards loading, test alert reaching the notification channel. The tier isn't complete until the full pipeline is proven end-to-end.

## Read first

Before implementing any plan:

1. **`CLAUDE.md`** — gem architecture, conventions
2. **`lib/pcs/service/dnsmasq.rb`** and **`lib/pcs/service/netboot.rb`** — reference implementations for the service pattern (start/stop/reload/status/status_report/log_command)
3. **`lib/pcs/service.rb`** — service registry (`MANAGED` constant, `resolve`, `managed_names`)
4. **`lib/pcs/config.rb`** — `ServiceSettings`, `Config#service` DSL pattern
5. **`lib/pcs/commands/services_command.rb`** — CLI commands that drive services
6. **`docs/cluster-formation/ADR-003-data-model-reference.md`** — host model, network model

## Plans

| Plan | Target | Key Deliverables |
|------|--------|-----------------|
| 01 | Prometheus + node exporters | Prometheus on RPi, node-exporter on PVE/NAS/VyOS, scrape targets generated |
| 02 | Alertmanager + notifications | Alertmanager on RPi, webhook/Google Chat routing, alert rules, test alert |
| 03 | Grafana | Grafana on RPi, Prometheus datasource, infrastructure dashboards |

Plans are sequential: Prometheus first (data source), then Alertmanager (consumes Prometheus), then Grafana (visualizes Prometheus).

## Completion Criteria

Operations tier is complete when:

- `pcs service status prometheus` shows all scrape targets up
- `pcs service status alertmanager` shows webhook endpoint configured and reachable
- `pcs service status grafana` shows datasource connected and dashboards loaded
- A simulated node-down condition triggers an alert that reaches Google Chat within 5 minutes
- `pcs service reload prometheus` regenerates scrape config after a host is added to IPAM
- All three services survive an RPi reboot (Podman restart policies)

## What is NOT in this tier

- **Application-level monitoring** — Rails metrics, Solana node health, tenant-specific exporters. That's an L3 tenant concern.
- **Log aggregation** — Loki/Promtail. Valuable but separate from metrics. Can be added as a future plan.
- **Uptime monitoring** — External probes (e.g., from another site checking if this site is reachable). Deferred.
- **Custom dashboards per tenant** — Operations tier covers infrastructure dashboards only.
