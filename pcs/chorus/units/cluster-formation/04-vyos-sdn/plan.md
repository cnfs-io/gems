---
---

# Plan 04: VyOS Router + SDN

**Tier:** Cluster Formation
**Objective:** Correctness — deploy a single VyOS VM as the cluster edge router, configure Proxmox SDN with a VLAN zone, and verify the cloud platform is ready to accept tenant workloads.
**Depends on:** Plan 03 (storage registered — VyOS VM disk needs `nas-vmdisks`)
**Required before:** Nothing — this is the final plan in the Cluster Formation tier.

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/cluster-formation/ADR-003-data-model-reference.md` — **read this first**
- `docs/cluster-formation/ADR-002-cluster-formation-scope.md` — MVP constraints: single VyOS VM, no HA, no tenant provisioning
- `lib/pcs/adapters/ssh.rb` — `SSH.connect`, `SSH.port_open?`
- `lib/pcs/config.rb` — `config.ssh_key_path`
- `lib/pcs/models/host.rb` — `Host.where(type: "pve")`, `host.ip_on(:compute)`
- `lib/pcs/models/state.rb` — `state.update_service`, `state.save!`
- `lib/pcs/providers/proxmox/cluster.rb` — SSH/pvesh patterns from Plan 01
- `lib/pcs/providers/proxmox/storage.rb` — pvesh patterns from Plan 03

### What exists vs what needs to be built

**Already exists and should be reused:**
- `Adapters::SSH.connect` — for pvesh calls and VyOS SSH config
- `Adapters::SSH.port_open?` — for polling VyOS boot
- `Pcs::Host.where(type: "pve")` — to find first node for VM placement
- `Pcs::State#update_service` — use `:network` service key for VyOS/routing state

**Needs to be built:**
- `lib/pcs/providers/proxmox/router.rb`
- `lib/pcs/providers/proxmox/sdn.rb`
- CLI commands: `pcs router create`, `pcs router configure`, `pcs router status`, `pcs sdn create`

**MVP constraints (do not add Production/Platform features):**
- Single VyOS VM — no VRRP, no active/passive failover
- Static routes only — no BGP, no OSPF
- North/south routing only (in and out of cluster)
- One VLAN zone in Proxmox SDN
- VNet creation is out of scope (tenant provisioning handles that)

---

## Network Design (MVP)

```
Internet / Uplink
      |
  vmbr0  (bridge to physical uplink NIC — already exists on PVE nodes)
      |
  VyOS VM (vmid 100, placed on first PVE node)
      eth0 — WAN: static IP on compute/management network
      eth1 — LAN: 802.1Q trunk (future tenant VLANs)
      |
  vmbr1  (trunk bridge — no IP, VLAN-aware — created by this plan)
      |
  Proxmox SDN
    VLAN Zone: "pcs-zone" (created by this plan)
      VNets created later by tenant provisioning system
```

VyOS WAN IP: from host model — a host entry for `vyos` with type `"vyos"` (or `"vm"`).
VyOS is configured with NAT masquerade so tenant VMs can reach the internet through it.

---

## Implementation Spec

### Provider: `Pcs::Providers::Proxmox::Router`

```ruby
def initialize(first_host, config, state)
```

SSH helpers:
```ruby
def ssh(ip, &block)
  Adapters::SSH.connect(host: ip, key: config.ssh_key_path, user: "root", &block)
end

def vyos_ssh(ip, &block)
  Adapters::SSH.connect(host: ip, key: config.ssh_key_path, user: "vyos", &block)
end
```

---

### `check_iso(first_host)`

VyOS does not provide free prebuilt ISOs — operators must build or source one. Verify the ISO is present before proceeding.

```bash
pvesh get /nodes/{first_host.hostname}/storage/nas-iso/content --output-format json
```

Parse — find an entry with name matching `vyos*.iso`. If not found, print instructions and raise:

```
VyOS ISO not found in nas-iso storage.
Upload a VyOS ISO to nas-iso storage first:
  PVE web UI → Datacenter → nas-iso → Upload ISO
Then re-run: pcs router create
```

Return the full storage path (e.g. `"nas-iso:iso/vyos-rolling-202501-amd64.iso"`).

---

### `ensure_vmbr1(cluster_hosts)`

VyOS needs a VLAN-aware trunk bridge on PVE nodes for its LAN interface. Must be created on **all cluster nodes** (so tenant VMs on any node can use SDN VNets).

On each cluster node via SSH, check `/etc/network/interfaces` for `vmbr1`. If absent, append:

```
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
```

Then: `ifreload -a`

---

### `create_vm(first_host, iso_path)`

Run pvesh on `first_host.ip_on(:compute)`. VMID 100 reserved for VyOS.

#### Check if exists

```bash
pvesh get /nodes/{first_host.hostname}/qemu/100/status/current --output-format json 2>/dev/null
```

If exit 0, VM exists — skip creation.

#### Create VM

```bash
pvesh create /nodes/{first_host.hostname}/qemu \
  --vmid 100 \
  --name vyos \
  --memory 512 \
  --cores 1 \
  --net0 virtio,bridge=vmbr0 \
  --net1 virtio,bridge=vmbr1,trunks=100-200 \
  --ide2 {iso_path},media=cdrom \
  --boot order=ide2 \
  --ostype l26
```

#### Allocate disk

```bash
pvesh create /nodes/{first_host.hostname}/qemu/100/config \
  --scsi0 nas-vmdisks:4
```

---

### `start_vm(first_host)`

```bash
pvesh create /nodes/{first_host.hostname}/qemu/100/status/start
```

Print instructions for operator to complete VyOS installation via console:
```
VyOS VM is starting. Complete the installation manually:
  1. Open PVE console: https://{first_host.ip_on(:compute)}:8006 → node → VM 100 → Console
  2. Boot from ISO and run: install image
  3. After install completes, remove ISO and reboot
  4. Once VyOS boots to login prompt, run: pcs router configure
```

---

### `configure_vyos(vyos_ip, compute_gateway, domain)`

SSH to VyOS as user `vyos`. VyOS uses its own shell — wrap all config commands:

```bash
vbash -c "
source /opt/vyatta/etc/functions/script-template
configure
set interfaces ethernet eth0 address {vyos_ip}/24
set interfaces ethernet eth0 description WAN
set protocols static route 0.0.0.0/0 next-hop {compute_gateway}
set system host-name vyos
set system domain-name {domain}
set service ssh port 22
set system ntp server 0.pool.ntp.org
set nat source rule 100 outbound-interface name eth0
set nat source rule 100 source address 10.0.0.0/8
set nat source rule 100 translation address masquerade
set firewall ipv4 forward filter rule 10 action accept
set firewall ipv4 forward filter rule 10 state established enable
set firewall ipv4 forward filter rule 10 state related enable
set firewall ipv4 forward filter rule 20 action accept
set firewall ipv4 forward filter rule 20 source address 10.0.0.0/8
set firewall ipv4 forward filter default-action drop
commit
save
exit
"
```

`vyos_ip` = VyOS WAN IP from host model.
`compute_gateway` = compute network gateway.
`domain` = site domain.

Update state:
```ruby
state.update_service(:network, "active", vyos_ip: vyos_ip)
state.save!
```

---

### Provider: `Pcs::Providers::Proxmox::SDN`

```ruby
def initialize(first_host, config)
```

---

### `create_zone`

```bash
pvesh get /cluster/sdn/zones/pcs-zone --output-format json 2>/dev/null
```

If not found:
```bash
pvesh create /cluster/sdn/zones \
  --zone pcs-zone \
  --type vlan \
  --bridge vmbr1
```

Apply SDN:
```bash
pvesh set /cluster/sdn
```

---

### `status`

Query VyOS and SDN state. Print: VyOS reachability, interface status, routing table, SDN zone info.

---

## Commands

### `pcs router create`

1. Load config, state; find `first_host = Pcs::Host.where(type: "pve").sort_by(&:hostname).first`
2. `cluster_hosts = Pcs::Host.where(type: "pve")`
3. Build `router = Providers::Proxmox::Router.new(first_host, config, state)`
4. Call `router.check_iso(first_host)` — exits with instructions if ISO missing
5. Call `router.ensure_vmbr1(cluster_hosts)`
6. Call `router.create_vm(first_host, iso_path)`
7. Call `router.start_vm(first_host)`
8. Print manual install instructions, exit

### `pcs router configure`

Separate command — called after operator confirms VyOS is installed and SSH is up.

1. Load config, state
2. Resolve VyOS IP from host model (type `"vyos"` or `"vm"`)
3. Resolve compute gateway and domain from network/site models
4. Call `router.configure_vyos(vyos_ip, compute_gateway, domain)`

### `pcs router status`

SSH to VyOS, run `show interfaces`, `show ip route`, `show nat source rules`. Print summary.

### `pcs sdn create`

1. Load config; find `first_host`
2. `sdn = Providers::Proxmox::SDN.new(first_host, config)`
3. Call `sdn.create_zone`

---

## Data Dependencies

- Plan 03 complete: `nas-vmdisks` storage registered and usable
- VyOS host entry in host model (type `"vyos"`, compute IP assigned)
- VyOS ISO uploaded to `nas-iso` storage manually before `pcs router create`
- `vmbr0` present on all PVE nodes (created during node provisioning)

---

## Testing Approach

1. After `pcs router create` + manual VyOS install + `pcs router configure`:
   - `ping {vyos_wan_ip}` from control plane RPi
   - `ssh vyos@{vyos_wan_ip}` — expect login
   - VyOS: `run show ip route` — expect default route via compute gateway

2. After `pcs sdn create`:
   - `pvesh get /cluster/sdn/zones --output-format json` — expect `pcs-zone`

3. End-to-end verification (manual):
   - Create a test VNet manually: `pvesh create /cluster/sdn/vnets --vnet test-100 --zone pcs-zone --tag 100`
   - Apply SDN: `pvesh set /cluster/sdn`
   - Add a VLAN sub-interface on VyOS for VLAN 100 with DHCP server (manual config)
   - Create a test VM on `nas-vmdisks` with NIC on `test-100`
   - VM should get DHCP address from VyOS
   - VM should reach internet via VyOS NAT
   - Clean up test VNet and VM after verification

Cluster Formation tier is complete when the end-to-end verification passes.
