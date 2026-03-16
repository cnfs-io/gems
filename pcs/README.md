# PCS — Private Cloud Stack

PCS is a Ruby CLI for bootstrapping bare-metal private cloud sites. It runs on a Raspberry Pi control plane and takes you from an empty rack to a running Proxmox VE cluster with network-attached storage, using PXE boot and automated provisioning.

## What PCS manages

PCS is the L2 (cloud provider) layer. It assumes L1 networking (VLANs, DHCP, physical switching) is already handled — in our case by UniFi gear managed separately. PCS takes over once hosts have DHCP-assigned IPs on the servers network and handles everything from there: host discovery, OS installation, static IP assignment, cluster formation.

## Prerequisites

- **Raspberry Pi** (4 or 5, arm64) running Debian/Ubuntu, connected to the servers network
- **Ruby 3.1+** installed via mise or similar
- **nmap** installed (`sudo apt install nmap`)
- **podman** installed (`sudo apt install podman`) for the netboot container
- **SSH key** for passwordless access to provisioned hosts
- L1 networking operational: DHCP serving the servers VLAN, all hosts connected and powered on

## Installation

PCS is distributed as a Ruby gem via ppm (private package manager):

```sh
ppm install pcs
```

Dependencies `flat_record` and `rest_cli` are sibling gems installed alongside PCS.

## Workflow: zero to Proxmox cluster

### 1. Create a project

```sh
pcs new rws-pcs
cd rws-pcs
```

This scaffolds the project structure:

```
rws-pcs/
  pcs.rb          # project marker + config DSL
  data/
    roles.yml     # role→type mappings (node, nas, kvm, cp)
  sites/          # per-site data (created by `pcs site add`)
  .gitignore
  README.md
```

### 2. Add a site

```sh
pcs site add sg
```

The interactive wizard prompts for domain, timezone, SSH key path, and network definitions. It auto-detects your current network for sensible defaults.

This creates `sites/sg/` with:
- `site.yml` — domain, timezone, SSH key reference
- `networks.yml` — at minimum a primary (compute) network
- `hosts.yml` — the RPi itself, registered as the control plane host
- `interfaces.yml` — the RPi's interface on the compute network

You can add additional networks (e.g., storage) during the wizard or later:

```sh
pcs network add storage
```

### 3. Set the active site

If you have multiple sites, select which one you're operating on:

```sh
pcs site use sg
```

This writes `PCS_SITE=sg` to `.env`. All subsequent commands target this site.

### 4. Configure the control plane

On the Raspberry Pi:

```sh
pcs cp setup
```

This sets the hostname, assigns a static IP on the compute network, and configures DNS. Your SSH session will disconnect after the network restart — reconnect at the new IP.

### 5. Scan the network

```sh
pcs network scan
```

Runs an nmap scan of the primary network. Discovered hosts are added to the inventory with MAC addresses and IPs, tracked via Interface records on the scanned network.

```sh
pcs host list
```

Shows all discovered hosts. They'll have status `discovered` with no role or type assigned yet.

### 6. Configure hosts

For each discovered host, assign its role and type:

```sh
pcs host update 6
```

The interactive prompt walks through: role (node, nas, kvm, cp), type (proxmox, truenas, pikvm, rpi), hostname, and architecture. This sets the host status to `configured`.

Alternatively, set fields directly:

```sh
pcs host update 6 role node
pcs host update 6 type proxmox
pcs host update 6 hostname n1c1
```

### 7. Start PXE boot services

```sh
pcs service start dnsmasq
pcs service start netboot
```

**dnsmasq** runs as a PXE proxy — it doesn't serve DHCP (that's L1), it only tells booting hosts where to find the TFTP/HTTP server for PXE.

**netboot** runs a netboot.xyz container via Podman. On start, it generates per-host iPXE menus, preseed files, and post-install scripts based on the configured inventory. When a host PXE boots, it gets a MAC-specific boot script that automates the Debian installation with the right hostname, static IP, and SSH keys.

After changing host configuration, regenerate the boot files:

```sh
pcs service reload netboot
```

### 8. PXE boot the nodes

Power on (or reboot to PXE) your bare-metal nodes. The boot sequence:

1. Host DHCP boots, gets IP from L1
2. dnsmasq proxy tells it about the PXE server (the RPi)
3. Host loads iPXE from netboot.xyz container
4. Custom iPXE chain: MAC-specific script → PCS menu → netboot.xyz fallback
5. MAC script triggers automated Debian install with preseed
6. Post-install script runs, host reboots into Debian with static IP and SSH access

### 9. Install Proxmox VE

Once hosts are running Debian (reachable at their compute IPs):

```sh
pcs cluster install
```

For each configured proxmox node, this SSHes in and:
- Sets hostname and /etc/hosts with all cluster peers
- Adds the Proxmox VE apt repository
- Installs `proxmox-ve`, `postfix`, `open-iscsi`, `chrony`
- Configures network interfaces (bridges for compute + optional storage)
- Enables iSCSI services
- Reboots and waits for the PVE web UI to come up
- Verifies `pveversion` on the compute IP

Install a single node:

```sh
pcs cluster install n1c1
```

### 10. Verify

```sh
pcs service status dnsmasq
pcs service status netboot
pcs host list
pcs site show sg
```

The Proxmox web UI is accessible at `https://<compute_ip>:8006` for each node.

## Command reference

### Project

| Command | Description |
|---------|-------------|
| `pcs new <name>` | Scaffold a new project |
| `pcs version` | Print version |
| `pcs console` | Start a Pry console with all models loaded |

### Sites

| Command | Description |
|---------|-------------|
| `pcs site list` | List all sites (* marks active) |
| `pcs site show <name>` | Show site details with networks |
| `pcs site add <name>` | Interactive site creation wizard |
| `pcs site update [field] [value]` | Update site settings |
| `pcs site use <name>` | Set the active site |
| `pcs site remove <name>` | Remove a site and its data |

### Hosts

| Command | Description |
|---------|-------------|
| `pcs host list` | List all hosts for the active site |
| `pcs host show <id>` | Show host details with interfaces |
| `pcs host add` | Interactively add a host |
| `pcs host update [id] [field] [value]` | Update host configuration |
| `pcs host remove <id>` | Remove a host |

### Networks

| Command | Description |
|---------|-------------|
| `pcs network list` | List networks for the active site |
| `pcs network show <name>` | Show network details with interfaces |
| `pcs network add <name>` | Add a network |
| `pcs network update <name> [field] [value]` | Update a network |
| `pcs network remove <name>` | Remove a network |
| `pcs network scan [name]` | Scan a network for hosts (Linux only) |

### Services (Linux only)

| Command | Description |
|---------|-------------|
| `pcs service list` | List all managed services |
| `pcs service show <name>` | Show service status |
| `pcs service start <name>` | Start a service |
| `pcs service stop <name>` | Stop a service |
| `pcs service restart <name>` | Full restart |
| `pcs service reload <name>` | Regenerate config, minimal restart |
| `pcs service status <name>` | Detailed diagnostics and recent logs |
| `pcs service status <name> -f` | Follow log output |

Managed services: `dnsmasq`, `netboot`

### Cluster (Linux only)

| Command | Description |
|---------|-------------|
| `pcs cluster install [node]` | Install Proxmox VE on configured nodes |

### Control plane (Linux only)

| Command | Description |
|---------|-------------|
| `pcs cp setup` | Configure RPi as control plane (hostname, static IP) |

## Data model

PCS uses FlatRecord (YAML-backed flat-file ORM) with a site hierarchy. All per-site data lives in `sites/<site_name>/`:

- **Site** — domain, timezone, SSH key. Hierarchy parent for all other models.
- **Host** — bare-metal machine. STI subclasses: PveHost (Proxmox), TruenasHost, PikvmHost, RpiHost. Status lifecycle: discovered → configured → installing → provisioned.
- **Network** — subnet definition (compute, storage, etc.). One primary network per site.
- **Interface** — joins a Host to a Network with MAC, IP, and NIC name.
- **Role** — read-only mapping of roles (node, nas, kvm, cp) to allowed host types and IP base octets.
- **Profile** — read-only provisioning defaults with parent-chain inheritance.

## Configuration

The `pcs.rb` file at the project root is both the project marker and configuration DSL:

```ruby
Pcs.configure do |config|
  config.flat_record do |fr|
    fr.backend = :yaml
    fr.hierarchy model: :site, key: :name
  end

  config.networking do |net|
    net.dns_fallback_resolvers = ["1.1.1.1", "8.8.8.8"]
  end

  config.service.dnsmasq do |dns|
    dns.proxy = true  # proxy DHCP mode (L1 serves DHCP)
  end

  config.service.netboot do |nb|
    nb.image = "docker.io/netbootxyz/netbootxyz"
    nb.default_os = "debian-trixie"
  end

  config.service.proxmox do |pve|
    pve.default_preseed_interface = "enp1s0"
    pve.default_preseed_device = "/dev/sda"
  end

  config.discovery do |d|
    d.users = %w[root admin pi]
    d.passwords = %w[changeme123! root admin raspberry]
  end
end

Pcs::Site.top_level_domain = "me.internal"
```

## Architecture

```
CLI (dry-cli + RestCli::Registry)
  → Commands (resource CRUD + service management)
    → Views (RestCli::View — table and detail rendering)
    → Models (FlatRecord::Base — YAML persistence)
    → Services (Dnsmasq, Netboot, ControlPlane)
    → Adapters (SSH, Nmap, Dnsmasq config, SystemCmd)
    → Providers (Proxmox::Installer)
    → Platform (Arch, Os — architecture/OS detection)
```

Commands are gated by context: some run anywhere (`new`, `version`), most require a project (`host`, `site`, `network`), and some are Linux-only (`service`, `cluster`, `cp`).

## Development

```sh
bundle exec rspec              # unit specs
bundle exec rspec spec/e2e/    # E2E tests (Linux + QEMU required)
```

## License

MIT
