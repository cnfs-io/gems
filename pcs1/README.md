# PCS1 — Private Cloud Stack

PCS is an interactive CLI for bootstrapping bare-metal private cloud sites. It runs on a Raspberry Pi control plane and manages the full lifecycle from network discovery through Proxmox cluster formation.

## Overview

PCS manages three layers of infrastructure:

- **L1** — Physical network (UniFi, managed separately)
- **L2** — Cloud provider (Proxmox VE clusters, managed by PCS)
- **L3** — Tenant workloads (VMs, containers, managed separately)

PCS handles L2: discovering hosts on the network, configuring their IPs via DHCP reservations, PXE-booting bare metal into Debian, and upgrading Debian hosts to Proxmox VE.

## Prerequisites

- Raspberry Pi (or any Debian-based machine) as the control plane
- Ruby 3.2+
- `nmap` installed (`sudo apt install nmap`)
- `dnsmasq` installed (`sudo apt install dnsmasq`)
- `podman` installed (`sudo apt install podman`)
- An SSH key pair on the control plane

## Quick Start

### 1. Create a project

```
pcs1 new sg
cd sg
```

This scaffolds a project directory with:

```
sg/
  pcs.rb              # project configuration
  data/
    sites.yml          # site record
    hosts.yml          # host records
    networks.yml       # network records
    interfaces.yml     # interface records
```

The `pcs1 new` wizard prompts for:

- **Site name** — identifier for this location (e.g., `sg`)
- **Domain** — local domain (e.g., `sg.local`)
- **Timezone** — for preseed installs
- **SSH key** — path to your public key file (default: `~/.ssh/authorized_keys`)
- **Control plane hostname** — name for this machine (default: `cp1`)
- **Host type** — select `debian`
- **Architecture** — `arm64` or `amd64`
- **Networks** — detected from local IPs, prompts for subnet, gateway, DNS

### 2. Edit configuration

Open `pcs.rb` to review and edit:

```ruby
Pcs1.configure do |config|
  # Default credentials per host type
  config.host_defaults = {
    "pikvm"   => { user: "root", password: "root" },
    "jetkvm"  => { user: "root", password: "root" },
    "debian"  => { user: "root", password: "changeme123!" },
    "proxmox" => { user: "root", password: "changeme123!" },
  }

  # Dnsmasq
  # config.dnsmasq.interface = "eth0"
  # config.dnsmasq.lease_time = "12h"

  # Netboot
  # config.netboot.netboot_dir = "/opt/pcs/netboot"

  # Logging
  # config.log_level = :debug
end
```

### 3. Start services

```
pcs1 service start dnsmasq
pcs1 service start netboot
pcs1 service status
```

This starts:
- **dnsmasq** — DHCP server with PXE boot support
- **netboot** — netboot.xyz container providing TFTP and HTTP for PXE

### 4. Scan the network

```
pcs1 network scan
```

Runs `nmap` on the primary network. Discovered hosts appear with status `discovered` and their DHCP-assigned IPs and MAC addresses.

```
pcs1 host list
```

### 5. Configure hosts

```
pcs1 host configure
```

Walks through each discovered host. For each one, you set:

- **Hostname** — e.g., `n1c1`, `kvm1`
- **Role** — e.g., `compute`, `kvm`
- **Type** — `debian`, `pikvm`, `jetkvm`, `truenas`
- **Architecture** — `amd64` or `arm64`
- **PXE boot** — yes/no (for bare-metal nodes that need OS installation)
- **Static IP** — the IP this host should have (per interface)
- **NIC name** — the network interface name (per interface)

When a host transitions to `configured`:
1. dnsmasq config is regenerated with DHCP reservations (MAC → IP)
2. Netboot PXE files are regenerated for PXE targets

### 6. Provision KVM devices

For hosts that are already running their OS (PiKVM, JetKVM):

```
pcs1 host provision 3
```

This:
1. Restarts networking on the host (to pick up the DHCP reservation)
2. Waits for the host to come back
3. Verifies SSH access at the configured IP
4. Transitions the host to `provisioned`

**PiKVM keying:** Before provisioning, push the SSH key:

```
pcs1 console
> host = Host.find("3")
> host.key!          # SSH in with default creds, push key
> host.key_access?   # verify key-based SSH works
```

**JetKVM keying:** Upload the SSH key via the JetKVM web UI, then verify:

```
pcs1 console
> host = Host.find("4")
> host.key_access?   # verify key-based SSH works
```

### 7. Install OS on bare-metal nodes

For hosts marked with `pxe_boot: true`:

```
pcs1 host install 5
```

This:
1. Ensures dnsmasq and netboot services are running
2. Generates PXE boot files (preseed, iPXE scripts)
3. Guides you to PXE boot the host
4. Waits for the host to come online after installation
5. Verifies SSH access and transitions to `provisioned`

The Debian preseed automates the entire installation: partitioning, packages, SSH keys, static networking, hostname. No manual interaction required during install.

### 8. Upgrade to Proxmox

Once a Debian host is provisioned, upgrade it to Proxmox:

```
pcs1 host upgrade 5 proxmox
```

This:
1. Changes the host type from `debian` to `proxmox`
2. Runs the Proxmox VE installation script (adds repo, installs packages, enables iSCSI)
3. Reboots the host
4. Verifies `pveversion` runs successfully

### 9. Form a Proxmox cluster

Cluster formation is done from the console:

```
pcs1 console

# First node creates the cluster
> master = Host.find("5")
> master.create_cluster!(cluster_name: "sg")

# Additional nodes join
> node = Host.find("6")
> node.join_cluster!(master_host: master)
```

## Host Lifecycle

### State machine

Every host follows the same base lifecycle:

```
discovered → keyed → configured → provisioned
```

- **discovered** — found by network scan (MAC + DHCP IP)
- **keyed** — SSH key access verified
- **configured** — hostname, type, IPs assigned; dnsmasq reservation written
- **provisioned** — reachable at configured IP, operational

### STI host types

Each host type customizes the lifecycle:

| Type | PXE | Key method | Provisioning |
|------|-----|------------|--------------|
| `debian` | Yes (if pxe_boot) | Preseed (auto) | PXE install |
| `pikvm` | No | SSH key push | Restart networking |
| `jetkvm` | No | Web UI upload | Restart networking |
| `proxmox` | No | Inherited | Inherited |
| `truenas` | No | SSH key push | Restart networking |

### Proxmox lifecycle

After a host is upgraded to `proxmox`, it has an additional state machine:

```
pending → pve_installed → networks_validated → clustered
```

## Commands

### Project
| Command | Description |
|---------|-------------|
| `pcs1 new <name>` | Create a new project |
| `pcs1 console` | Open a Pry console |
| `pcs1 version` | Print version |

### Hosts
| Command | Description |
|---------|-------------|
| `pcs1 host list` | List all hosts |
| `pcs1 host show <id>` | Show host details |
| `pcs1 host add` | Add a host manually |
| `pcs1 host update [id]` | Update a host |
| `pcs1 host configure` | Walk through discovered hosts |
| `pcs1 host provision [id]` | Provision a configured host |
| `pcs1 host install [id]` | PXE install OS on a host |
| `pcs1 host upgrade [id] [type]` | Upgrade a provisioned host |
| `pcs1 host remove <id>` | Remove a host |

### Networks
| Command | Description |
|---------|-------------|
| `pcs1 network list` | List networks |
| `pcs1 network show <id>` | Show network details |
| `pcs1 network scan [name]` | Scan a network for hosts |
| `pcs1 network add` | Add a network |
| `pcs1 network update <id>` | Update a network |
| `pcs1 network remove <id>` | Remove a network |

### Services
| Command | Description |
|---------|-------------|
| `pcs1 service start <name>` | Start dnsmasq or netboot |
| `pcs1 service stop <name>` | Stop a service |
| `pcs1 service status [name]` | Show status (one or all) |
| `pcs1 service restart <name>` | Restart a service |

### Templates
| Command | Description |
|---------|-------------|
| `pcs1 template list` | List available templates |
| `pcs1 template customize <path>` | Copy a template into project for editing |
| `pcs1 template reset <path>` | Revert a customized template to gem default |

## Templates

PCS uses ERB templates for all generated config files. Templates resolve project-first: if a template exists in `<project>/templates/`, it's used instead of the gem default.

To customize a template:

```
pcs1 template list                           # see available templates
pcs1 template customize proxmox/install.sh.erb  # copy to project
vi templates/proxmox/install.sh.erb           # edit
```

Available templates:

| Template | Used by | Purpose |
|----------|---------|---------|
| `dnsmasq.conf.erb` | Dnsmasq | DHCP + PXE boot config |
| `debian/preseed.cfg.erb` | DebianHost | Automated Debian install |
| `debian/post-install.sh.erb` | DebianHost | Post-install hook |
| `proxmox/install.sh.erb` | PveHost | Proxmox VE installation |
| `proxmox/create-cluster.sh.erb` | PveHost | Cluster creation |
| `proxmox/join-cluster.sh.erb` | PveHost | Cluster join |
| `netboot/pcs-menu.ipxe.erb` | Netboot | iPXE boot menu |
| `netboot/mac-boot.ipxe.erb` | Netboot | Per-MAC boot script |
| `netboot/custom.ipxe.erb` | Netboot | netboot.xyz custom hook |

## Configuration

All configuration lives in `pcs.rb` at the project root.

### Host defaults

```ruby
config.host_defaults = {
  "pikvm"  => { user: "root", password: "root" },
  "debian" => { user: "root", password: "changeme123!", wait_attempts: 60 },
}
```

Per-type fields: `user`, `password`, `wait_attempts`, `wait_interval`.

### Global host settings

```ruby
config.host.wait_attempts = 30   # polls after reboot (default)
config.host.wait_interval = 5    # seconds between polls (default)
```

### Dnsmasq

```ruby
config.dnsmasq.config_path = "/etc/dnsmasq.d/pcs.conf"
config.dnsmasq.interface = "eth0"
config.dnsmasq.lease_time = "12h"
config.dnsmasq.range_start_octet = 100
config.dnsmasq.range_end_octet = 200
```

### Netboot

```ruby
config.netboot.image = "docker.io/netbootxyz/netbootxyz"
config.netboot.netboot_dir = "/opt/pcs/netboot"
config.netboot.tftp_port = 69
config.netboot.http_port = 8080
config.netboot.web_port = 3000
config.netboot.boot_file_bios = "netboot.xyz.kpxe"
config.netboot.boot_file_efi = "netboot.xyz.efi"
config.netboot.boot_file_arm64 = "netboot.xyz-arm64.efi"
```

### Logging

```ruby
config.log_level = :info                      # :debug, :info, :warn, :error
config.log_output = $stdout                    # or File.open("log/pcs.log", "a")
```

## Architecture

### Models

- **Site** — singleton per project (name, domain, timezone, SSH key)
- **Host** — STI base class with state machine (discovered → keyed → configured → provisioned)
- **Network** — subnet, gateway, DNS (has_many interfaces)
- **Interface** — MAC, discovered_ip, configured_ip (belongs_to host + network)

### Host STI hierarchy

```
Host (base)
├── DebianHost    — PXE/preseed, networking via nmcli/systemctl
├── PikvmHost     — SSH key push with rw/ro, reboot to provision
├── JetkvmHost    — manual key upload, reboot to provision
├── PveHost       — Proxmox VE with its own pve_status state machine
└── (TrueNasHost) — future
```

### Services

- **Dnsmasq** — DHCP with MAC reservations + PXE boot directions
- **Netboot** — netboot.xyz Podman container, PXE file generation

Both inherit from `Service` base class. Both read from `Pcs1.site` and `Pcs1.config`. Templates resolve via `Pcs1.resolve_template` (project-first, gem fallback).

### Key design principles

- **One project per site** — each physical location is its own project directory
- **Site resolution via network** — PCS knows which site it's at by matching local IPs against configured interfaces
- **Network-first iteration** — dnsmasq iterates network interfaces, not hosts
- **Host types own their install files** — each STI subclass generates its own preseed/kickstart/etc.
- **Fat models, extract later** — domain logic on models, services extracted when needed
- **Externalized scripts** — Proxmox installation via ERB templates, replaceable with Ansible
- **Convention over configuration** — STI types auto-register, templates auto-resolve
