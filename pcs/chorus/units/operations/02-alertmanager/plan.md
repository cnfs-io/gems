---
---

# Plan 02: Alertmanager + Notifications

**Tier:** Operations
**Objective:** Deploy Alertmanager on the control plane, configure alert rules in Prometheus, set up webhook and Google Chat notifications, and verify the full alerting pipeline end-to-end.
**Depends on:** Plan 01 (Prometheus running, all targets up)
**Required before:** Plan 03 (Grafana can show alert status from Alertmanager)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `lib/pcs/service/prometheus.rb` — created in Plan 01, follow same patterns
- `lib/pcs/service/dnsmasq.rb` — reference for service pattern
- `lib/pcs/service.rb` — add `:Alertmanager` to `MANAGED`
- `lib/pcs/config.rb` — add `AlertmanagerSettings` with webhook URLs
- `lib/pcs/templates/prometheus/prometheus.yml.erb` — already references alertmanager at localhost:9093

### What exists vs what needs to be built

**Already exists (from Plan 01):**
- `Service::Prometheus` — running, scraping all targets
- `prometheus.yml.erb` — already has `alerting:` section pointing to `localhost:9093`
- `prometheus.yml.erb` — already has `rule_files: - /etc/prometheus/alerts.yml`
- Service pattern established and tested

**Needs to be built:**
- `lib/pcs/service/alertmanager.rb` — service class
- `lib/pcs/templates/alertmanager/alertmanager.yml.erb` — routing and receiver config
- `lib/pcs/templates/prometheus/alerts.yml.erb` — alert rules
- `AlertmanagerSettings` config class

---

## What This Plan Builds

### New service: `pcs service start alertmanager`

Alertmanager runs as a Podman container on the RPi. It receives alerts from Prometheus and routes them to configured notification channels.

### Alert rules deployed to Prometheus

A set of infrastructure alert rules covering the critical failure modes. These are generated as `alerts.yml` and mounted into the Prometheus container.

### New files to create
```
lib/pcs/service/alertmanager.rb
lib/pcs/templates/alertmanager/alertmanager.yml.erb
lib/pcs/templates/prometheus/alerts.yml.erb
```

---

## Implementation Spec

### Config: `AlertmanagerSettings`

```ruby
class AlertmanagerSettings
  attr_accessor :image, :port, :data_dir, :webhook_urls, :google_chat_webhooks,
                :repeat_interval, :group_wait, :group_interval

  def initialize
    @image = "docker.io/prom/alertmanager:latest"
    @port = 9093
    @data_dir = Pathname.new("/opt/pcs/alertmanager")
    @webhook_urls = []          # Generic webhook endpoints
    @google_chat_webhooks = []  # Google Chat space webhook URLs
    @repeat_interval = "4h"
    @group_wait = "30s"
    @group_interval = "5m"
  end
end
```

Configuration in `config/pcs.rb`:
```ruby
Pcs.configure do |c|
  c.service do |s|
    s.alertmanager do |am|
      am.google_chat_webhooks = [
        "https://chat.googleapis.com/v1/spaces/XXX/messages?key=YYY&token=ZZZ"
      ]
      am.webhook_urls = [
        "https://example.com/webhook/alerts"
      ]
    end
  end
end
```

### Service: `Pcs::Service::Alertmanager`

#### `start(site:, system_cmd:)`

1. Check Podman installed
2. Skip if already running
3. Ensure data directory: `/opt/pcs/alertmanager/data`, `/opt/pcs/alertmanager/config`
4. Generate configs: `write_config(system_cmd:)` and `write_alert_rules(system_cmd:)`
5. Pull image if not present
6. Start container:

```bash
podman run -d \
  --name alertmanager \
  --restart unless-stopped \
  --network host \
  -v /opt/pcs/alertmanager/config:/etc/alertmanager:ro \
  -v /opt/pcs/alertmanager/data:/alertmanager \
  {image} \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --web.listen-address=0.0.0.0:{port} \
  --storage.path=/alertmanager
```

7. Reload Prometheus to pick up alert rules (if Prometheus is running):
```bash
podman exec prometheus kill -HUP 1
```

#### `reload(site:, system_cmd:)`

Regenerate both configs and reload both services:
```bash
write_config(system_cmd:)
write_alert_rules(system_cmd:)
podman exec alertmanager kill -HUP 1   # reload alertmanager config
podman exec prometheus kill -HUP 1     # reload alert rules
```

#### `stop`, `status`, `status_report`, `log_command`

Follow established patterns from Dnsmasq/Netboot/Prometheus.

`status_report` should include:
- Container status
- Port 9093 listening
- Configured receivers (names only, not webhook URLs)
- Active alerts count: `curl -s http://localhost:9093/api/v2/alerts | jq 'length'`
- Recent notification log (if available)

### Config generation: `write_config(system_cmd:)`

#### Template: `alertmanager.yml.erb`

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: default
  group_by: ['alertname', 'host']
  group_wait: <%= group_wait %>
  group_interval: <%= group_interval %>
  repeat_interval: <%= repeat_interval %>
  routes:
    - receiver: critical
      match:
        severity: critical
    - receiver: warning
      match:
        severity: warning

receivers:
  - name: default
    webhook_configs:
<% webhook_urls.each do |url| %>
      - url: '<%= url %>'
        send_resolved: true
<% end %>
<% google_chat_webhooks.each do |url| %>
      - url: '<%= url %>'
        send_resolved: true
        http_config:
          follow_redirects: true
<% end %>

  - name: critical
    webhook_configs:
<% webhook_urls.each do |url| %>
      - url: '<%= url %>'
        send_resolved: true
<% end %>
<% google_chat_webhooks.each do |url| %>
      - url: '<%= url %>'
        send_resolved: true
        http_config:
          follow_redirects: true
<% end %>

  - name: warning
    webhook_configs:
<% webhook_urls.each do |url| %>
      - url: '<%= url %>'
        send_resolved: true
<% end %>
<% google_chat_webhooks.each do |url| %>
      - url: '<%= url %>'
        send_resolved: true
        http_config:
          follow_redirects: true
<% end %>
```

**Note on Google Chat:** Google Chat incoming webhooks accept a simple JSON payload (`{"text": "message"}`). Alertmanager's default webhook format sends a richer JSON body. This may need a translation layer — either:
- A lightweight webhook proxy container that reformats Alertmanager JSON -> Google Chat JSON
- Or use Alertmanager's template system to send Google Chat-compatible payloads

Investigate during implementation. If a proxy is needed, deploy it as a sidecar Podman container.

### Alert rules: `write_alert_rules(system_cmd:)`

#### Template: `alerts.yml.erb`

```yaml
groups:
  - name: node_health
    rules:
      - alert: NodeDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.host }} is unreachable"
          description: "{{ $labels.job }}/{{ $labels.host }} has been down for more than 2 minutes."

      - alert: HighCPU
        expr: 100 - (avg by(host) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.host }}"
          description: "CPU usage above 85% for 10 minutes on {{ $labels.host }}."

      - alert: HighMemory
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.host }}"
          description: "Memory usage above 90% for 10 minutes on {{ $labels.host }}."

      - alert: DiskSpaceLow
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 85
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low on {{ $labels.host }}"
          description: "Root filesystem above 85% on {{ $labels.host }}."

      - alert: DiskSpaceCritical
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 95
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk space critical on {{ $labels.host }}"
          description: "Root filesystem above 95% on {{ $labels.host }}. Immediate attention required."

  - name: cluster_health
    rules:
      - alert: ClusterNodeOffline
        expr: up{job="pve_nodes"} == 0
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "PVE node {{ $labels.host }} offline"
          description: "Proxmox node {{ $labels.host }} has been unreachable for 3 minutes."

      - alert: NASUnreachable
        expr: up{job="nas"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "TrueNAS unreachable"
          description: "TrueNAS has been unreachable for 2 minutes. Storage may be affected."

      - alert: RouterDown
        expr: up{job="router"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "VyOS router unreachable"
          description: "VyOS router has been down for 2 minutes. Tenant networking affected."

  - name: control_plane
    rules:
      - alert: ControlPlaneHighLoad
        expr: node_load1{job="control_plane"} > 3
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High load on control plane"
          description: "RPi load average above 3 for 10 minutes. Services may be degraded."

      - alert: PrometheusStorageFull
        expr: (1 - (node_filesystem_avail_bytes{job="control_plane",mountpoint="/"} / node_filesystem_size_bytes{job="control_plane",mountpoint="/"})) * 100 > 80
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Control plane disk filling up"
          description: "RPi root filesystem above 80%. Consider reducing Prometheus retention."
```

These rules cover the essential failure modes for the infrastructure layer. Additional rules can be added later without a plan — just edit `alerts.yml.erb` and `pcs service reload alertmanager`.

---

## Commands

No new CLI commands. Uses existing service CLI:

```
pcs service start alertmanager
pcs service stop alertmanager
pcs service reload alertmanager
pcs service status alertmanager
```

---

## Data Dependencies

- Plan 01 complete: Prometheus running, all targets up
- At least one notification endpoint configured in `config/pcs.rb` (webhook URL or Google Chat webhook)
- Prometheus container accessible for SIGHUP reload

---

## Testing Approach

1. After `pcs service start alertmanager`:
   - `curl http://localhost:9093/-/healthy` returns 200
   - `curl http://localhost:9093/api/v2/status` shows config loaded
   - `pcs service status alertmanager` shows running, receivers configured

2. Alert rules loaded in Prometheus:
   - `curl http://localhost:9090/api/v1/rules | jq '.data.groups | length'` — expect 3 groups
   - All rules show `"health": "ok"` (no evaluation errors)

3. **End-to-end test — simulated alert:**
   - Stop node-exporter on one PVE node: `ssh root@{pve_ip} systemctl stop prometheus-node-exporter`
   - Wait 3 minutes (NodeDown fires after 2m, ClusterNodeOffline after 3m)
   - Check active alerts: `curl http://localhost:9093/api/v2/alerts | jq 'length'` — expect >= 1
   - Verify notification received in Google Chat space (or webhook endpoint logs)
   - Restart node-exporter: `ssh root@{pve_ip} systemctl start prometheus-node-exporter`
   - Wait for resolved notification

4. After RPi reboot:
   - Both Prometheus and Alertmanager containers restart
   - Alert history preserved

Do not proceed to Plan 03 until the end-to-end alert test passes — a real notification must reach Google Chat.
