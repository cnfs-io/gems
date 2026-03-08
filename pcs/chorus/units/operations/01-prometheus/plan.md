---
---

# Plan 01: Prometheus + Node Exporters

**Tier:** Operations
**Objective:** Deploy Prometheus on the control plane RPi, enable node-exporter on all infrastructure hosts, and verify metrics are being scraped.
**Depends on:** Cluster Formation tier complete (all hosts reachable, cluster quorate).
**Required before:** Plan 02 (Alertmanager consumes Prometheus), Plan 03 (Grafana visualizes Prometheus)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `lib/pcs/service/dnsmasq.rb` — **reference implementation** for the service pattern. Prometheus follows this exact structure: `start`, `stop`, `reload`, `status`, `status_report`, `log_command` class methods.
- `lib/pcs/service/netboot.rb` — reference for Podman container lifecycle (pull, run, stop, inspect, logs)
- `lib/pcs/service.rb` — `MANAGED` constant, `resolve` method. Prometheus must be added here.
- `lib/pcs/config.rb` — `ServiceSettings` class, DSL pattern for service config. Add `PrometheusSettings`.
- `lib/pcs/commands/services_command.rb` — CLI commands. No changes needed — existing `pcs service start/stop/reload/status` commands will automatically pick up Prometheus once registered.
- `lib/pcs/models/host.rb` — `Host.where(type: "pve")`, `Host.all`, `host.ip_on(:compute)`, `host.hostname`
- `lib/pcs/adapters/ssh.rb` — `SSH.connect` for enabling exporters on remote hosts

### What exists vs what needs to be built

**Already exists and should be reused:**
- Service lifecycle pattern from `Service::Dnsmasq` and `Service::Netboot`
- Podman container management pattern from `Service::Netboot`
- `Adapters::SystemCmd` for local commands on the RPi
- `Adapters::SSH` for remote commands on PVE/NAS/VyOS hosts
- `Pcs::Host` model for generating scrape targets
- `pcs service start/stop/reload/status` CLI — already works for any registered service

**Needs to be built:**
- `lib/pcs/service/prometheus.rb` — service class
- `lib/pcs/templates/prometheus/prometheus.yml.erb` — scrape config template
- `PrometheusSettings` config class
- Registration in `Service::MANAGED`

**Needs updating:**
- `lib/pcs/service.rb` — add `:Prometheus` to `MANAGED`
- `lib/pcs/config.rb` — add `PrometheusSettings` and wire into `ServiceSettings`

---

## What This Plan Builds

### New service: `pcs service start prometheus`

Prometheus runs as a Podman container on the RPi control plane. It scrapes:
- Itself (Prometheus self-monitoring)
- node-exporter on each PVE node (port 9100)
- node-exporter on TrueNAS (port 9100)
- node-exporter on VyOS (port 9100)
- PVE exporter on each PVE node (port 9221, if available)
- The RPi control plane itself (node-exporter, port 9100)

### New files to create
```
lib/pcs/service/prometheus.rb
lib/pcs/templates/prometheus/prometheus.yml.erb
```

### Enabling exporters on remote hosts

Before Prometheus can scrape, exporters must be running on target hosts. This plan handles enabling them:

- **PVE nodes**: `pvenode exporter start` or install `prometheus-node-exporter` package. PVE 8.x ships with a built-in metrics endpoint — check availability.
- **TrueNAS**: Has a built-in Prometheus exporter (Graphite -> Prometheus bridge or native). Check `midclt call reporting.exporters`.
- **VyOS**: Install `node_exporter` via VyOS package or deploy as a container.
- **RPi (control plane)**: Install `prometheus-node-exporter` via apt, or run as Podman container.

---

## Implementation Spec

### Config: `PrometheusSettings`

```ruby
class PrometheusSettings
  attr_accessor :image, :retention, :port, :data_dir

  def initialize
    @image = "docker.io/prom/prometheus:latest"
    @retention = "30d"
    @port = 9090
    @data_dir = Pathname.new("/opt/pcs/prometheus")
  end
end
```

Wire into `ServiceSettings`:
```ruby
class ServiceSettings
  def prometheus
    @prometheus_config ||= PrometheusSettings.new
    yield @prometheus_config if block_given?
    @prometheus_config
  end
end
```

### Service: `Pcs::Service::Prometheus`

Follow the `Dnsmasq` / `Netboot` pattern exactly. Class methods:

#### `start(site:, system_cmd:)`

1. Check Podman installed
2. Skip if container already running
3. Ensure data directory exists (`/opt/pcs/prometheus/data`)
4. Generate config: `write_config(site:, system_cmd:)`
5. Pull image if not present
6. Remove existing container if stopped
7. Start Podman container:

```bash
podman run -d \
  --name prometheus \
  --restart unless-stopped \
  --network host \
  -v /opt/pcs/prometheus/config:/etc/prometheus:ro \
  -v /opt/pcs/prometheus/data:/prometheus \
  {image} \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.retention.time={retention} \
  --web.listen-address=0.0.0.0:{port}
```

Using `--network host` so Prometheus can reach all hosts on the compute network directly.

8. Enable exporters on remote hosts: `enable_exporters(site:, system_cmd:)`

#### `stop(system_cmd:)`

```bash
podman stop prometheus
podman rm prometheus
```

#### `reload(site:, system_cmd:)`

Regenerate config and signal Prometheus to reload:
```bash
# Regenerate prometheus.yml
write_config(site:, system_cmd:)
# Prometheus supports hot reload via SIGHUP or HTTP POST
podman exec prometheus kill -HUP 1
```

This is key — when a new host is added to IPAM, `pcs service reload prometheus` regenerates scrape targets and reloads without restart. No data loss.

#### `status(system_cmd:)`

Same pattern as Netboot — `podman inspect prometheus --format '{{.State.Status}}'`.

#### `log_command`

`"sudo podman logs -f prometheus"`

#### `status_report(system_cmd:, pastel:, lines:)`

Print:
- Container status (running/stopped, uptime, image)
- Port 9090 listening check
- Scrape target health: `curl -s http://localhost:9090/api/v1/targets` -> parse JSON, show each target with up/down status
- Storage: data directory size, retention setting
- Recent logs

### Config generation: `write_config(site:, system_cmd:)`

This is the core of the service — generating `prometheus.yml` from the host model.

```ruby
def self.write_config(site:, system_cmd:)
  config_dir = Pcs.config.service.prometheus.data_dir / "config"
  system_cmd.run!("mkdir -p #{config_dir}", sudo: true) unless config_dir.exist?

  # Gather all hosts
  pve_hosts = Pcs::Host.where(type: "pve")
  nas_hosts = Pcs::Host.where(type: "truenas")
  vyos_hosts = Pcs::Host.where(type: "vyos")  # or type "vm" with hostname "vyos"
  cp_host = Pcs::Host.find_by(role: "cp")

  template = ERB.new(PROMETHEUS_TEMPLATE.read, trim_mode: "-")
  content = template.result_with_hash(
    pve_hosts: pve_hosts,
    nas_hosts: nas_hosts,
    vyos_hosts: vyos_hosts,
    cp_host: cp_host,
    scrape_interval: "15s",
    evaluation_interval: "15s"
  )

  system_cmd.file_write(config_dir / "prometheus.yml", content, sudo: true)
end
```

### Template: `prometheus.yml.erb`

```yaml
global:
  scrape_interval: <%= scrape_interval %>
  evaluation_interval: <%= evaluation_interval %>

rule_files:
  - /etc/prometheus/alerts.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090

<% if cp_host %>
  - job_name: control_plane
    static_configs:
      - targets:
          - localhost:9100
        labels:
          host: <%= cp_host.hostname %>
          role: control_plane
<% end %>

<% unless pve_hosts.empty? %>
  - job_name: pve_nodes
    static_configs:
<% pve_hosts.each do |host| %>
      - targets:
          - <%= host.ip_on(:compute) %>:9100
        labels:
          host: <%= host.hostname %>
          type: pve
<% end %>
<% end %>

<% unless nas_hosts.empty? %>
  - job_name: nas
    static_configs:
<% nas_hosts.each do |host| %>
      - targets:
          - <%= host.ip_on(:compute) %>:9100
        labels:
          host: <%= host.hostname %>
          type: truenas
<% end %>
<% end %>

<% unless vyos_hosts.empty? %>
  - job_name: router
    static_configs:
<% vyos_hosts.each do |host| %>
      - targets:
          - <%= host.ip_on(:compute) %>:9100
        labels:
          host: <%= host.hostname %>
          type: vyos
<% end %>
<% end %>
```

### Enabling exporters: `enable_exporters(site:, system_cmd:)`

This runs once during `start` and can be called independently. Uses SSH to remote hosts.

#### PVE nodes

SSH to each PVE node:
```bash
# Check if node-exporter is already running
systemctl is-active prometheus-node-exporter 2>/dev/null && exit 0
# Install and enable
apt-get install -y prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
```

PVE 8.x also has a built-in metrics server. Check:
```bash
pvesh get /nodes/{node}/config --output-format json
```

Look for `metric-server-exporter` field. If available, use it instead of node-exporter for PVE-specific metrics (cluster status, VM counts, storage usage). This provides richer data than generic node-exporter.

#### TrueNAS

SSH to NAS:
```bash
# TrueNAS SCALE has reporting built in — check if Prometheus-compatible endpoint exists
midclt call reporting.exporters
```

If TrueNAS doesn't expose a native Prometheus endpoint, install node-exporter:
```bash
apt-get install -y prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
```

Note: TrueNAS SCALE is Debian-based, so apt works. But TrueNAS may overwrite changes on update. Document this limitation.

#### VyOS

SSH to VyOS as `vyos`:
```bash
# Check if node_exporter exists
which node_exporter && exit 0
# VyOS doesn't have apt in the usual sense — may need to download binary
curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz | tar xz
sudo mv node_exporter-*/node_exporter /usr/local/bin/
```

Create a systemd service for it:
```bash
sudo tee /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

#### RPi (control plane)

Local — no SSH needed:
```bash
apt-get install -y prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
```

---

## Commands

No new CLI commands. Prometheus is accessed via the existing service CLI:

```
pcs service start prometheus
pcs service stop prometheus
pcs service reload prometheus
pcs service status prometheus
pcs service status prometheus -f    # follow logs
```

The existing `ServicesCommand` automatically discovers Prometheus once it's added to `Service::MANAGED`.

---

## Data Dependencies

- All infrastructure hosts reachable via SSH on compute IPs
- Host model populated with PVE, TrueNAS, VyOS, and RPi entries
- Podman installed on RPi (already a prerequisite for netboot)
- RPi has sufficient disk space for Prometheus data (~1GB for 30d retention with small cluster)

---

## RPi Resource Considerations

Prometheus on a Raspberry Pi 400 is viable for a small cluster (3-5 nodes, 15s scrape interval). Expected resource usage:
- RAM: ~100-200MB for Prometheus with a small target set
- Disk: ~500MB-1GB for 30 days of retention at 15s intervals across ~10 targets
- CPU: Minimal — scraping and evaluating rules is lightweight

If the RPi becomes resource-constrained, the scrape interval can be increased to 30s or 60s, or retention reduced. These are configurable in `PrometheusSettings`.

---

## Testing Approach

1. After `pcs service start prometheus`:
   - `curl http://localhost:9090/-/healthy` returns 200
   - `curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'` — expect count matching number of hosts + 1 (self)
   - Each target shows `"health": "up"` in targets API
   - `pcs service status prometheus` shows all targets green

2. After adding a new host to IPAM + `pcs service reload prometheus`:
   - New target appears in `curl http://localhost:9090/api/v1/targets`
   - No Prometheus restart required, no data gap

3. After RPi reboot:
   - `podman ps` shows prometheus running (restart policy)
   - Historical data preserved in `/opt/pcs/prometheus/data`

4. Port checks from RPi:
   - Each PVE node: `curl http://{ip}:9100/metrics` returns metrics
   - NAS: `curl http://{nas_ip}:9100/metrics` returns metrics
   - VyOS: `curl http://{vyos_ip}:9100/metrics` returns metrics

Do not proceed to Plan 02 until all scrape targets show `"health": "up"`.
