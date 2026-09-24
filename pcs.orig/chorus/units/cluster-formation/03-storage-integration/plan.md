---
---

# Plan 03: Storage Integration

**Tier:** Cluster Formation
**Objective:** Correctness — register TrueNAS NFS and iSCSI storage in Proxmox, create the LVM-thin pool on the iSCSI LUN, and verify all storage is visible and usable across all cluster nodes.
**Depends on:** Plan 01 (cluster quorate) + Plan 02 (NAS provisioned, services running)
**Required before:** Plan 04 (VyOS + SDN)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/cluster-formation/ADR-003-data-model-reference.md` — **read this first**
- `lib/pcs/adapters/ssh.rb` — `SSH.connect`, `SSH.port_open?`
- `lib/pcs/config.rb` — `config.ssh_key_path`
- `lib/pcs/models/host.rb` — `Host.where(type: "pve")`, `Host.where(type: "truenas")`, `host.ip_on(:compute)`, `host.ip_on(:storage)`
- `lib/pcs/models/state.rb` — `state.update_service`, `state.save!`
- `lib/pcs/providers/proxmox/cluster.rb` — SSH and pvesh patterns from Plan 01

### What exists vs what needs to be built

**Already exists and should be reused:**
- `Adapters::SSH.connect` — for all pvesh calls
- `Providers::Proxmox::Cluster` — follow its SSH/pvesh patterns exactly

**Needs to be built:**
- `lib/pcs/providers/proxmox/storage.rb`
- CLI commands: `pcs storage register`, `pcs storage lvm-setup`, `pcs storage status`

---

## What This Plan Builds

### New commands
```
pcs storage register          # register NFS + iSCSI in Proxmox
pcs storage lvm-setup         # create LVM-thin pool on iSCSI LUN
pcs storage status            # verify storage visibility across cluster
```

---

## Implementation Spec

### Provider: `Pcs::Providers::Proxmox::Storage`

```ruby
# lib/pcs/providers/proxmox/storage.rb
def initialize(first_host, cluster_hosts, nas_host, config, state)
# first_host: Pcs::Host — runs pvesh commands here
# cluster_hosts: all Pcs::Host for PVE nodes
# nas_host: Pcs::Host for TrueNAS
```

SSH helper — same pattern as Plan 01:
```ruby
def ssh(ip, &block)
  Adapters::SSH.connect(host: ip, key: config.ssh_key_path, user: "root", &block)
end
```

Existence check:
```ruby
def storage_exists?(storage_id)
  ssh(first_host.ip_on(:compute)) do |s|
    result = s.exec!("pvesh get /storage/#{storage_id} --output-format json 2>/dev/null")
    true
  end
rescue => e
  e.message.include?("does not exist") ? false : raise
end
```

---

### `register_nfs`

Run all via pvesh on `first_host.ip_on(:compute)`. Storage config is cluster-wide.

Use `nas_host.ip_on(:storage)` as the NFS server — not the management IP.

#### ISO storage

```bash
pvesh create /storage \
  --storage nas-iso \
  --type nfs \
  --server {nas_host.ip_on(:storage)} \
  --export /mnt/tank/proxmox/isos \
  --content iso \
  --options vers=4
```

#### Template storage

```bash
pvesh create /storage \
  --storage nas-templates \
  --type nfs \
  --server {nas_host.ip_on(:storage)} \
  --export /mnt/tank/proxmox/templates \
  --content vztmpl \
  --options vers=4
```

#### Backup storage

```bash
pvesh create /storage \
  --storage nas-backup \
  --type nfs \
  --server {nas_host.ip_on(:storage)} \
  --export /mnt/tank/proxmox/backups \
  --content backup \
  --options vers=4
```

Each: check `storage_exists?` first, skip if present. Idempotent.

---

### `register_iscsi`

Target IQN: `iqn.2005-10.org.freenas.ctl:{cluster_name}-vmdisks`

```bash
pvesh create /storage \
  --storage nas-iscsi \
  --type iscsi \
  --portal {nas_host.ip_on(:storage)}:3260 \
  --target iqn.2005-10.org.freenas.ctl:{cluster_name}-vmdisks \
  --content none
```

Check `storage_exists?("nas-iscsi")` first.

---

### `connect_iscsi_on_nodes`

Before LVM can be created, each node must discover and log in to the iSCSI target. Run on **each cluster node** via SSH.

```bash
# Discover
iscsiadm -m discovery -t sendtargets -p {nas_host.ip_on(:storage)}:3260

# Login
iscsiadm -m node \
  --targetname iqn.2005-10.org.freenas.ctl:{cluster_name}-vmdisks \
  --portal {nas_host.ip_on(:storage)}:3260 \
  --login

# Persist login across reboots
iscsiadm -m node \
  --targetname iqn.2005-10.org.freenas.ctl:{cluster_name}-vmdisks \
  --portal {nas_host.ip_on(:storage)}:3260 \
  --op update \
  --name node.startup \
  --value automatic
```

After login on first node, identify the LUN block device:
```bash
lsblk --json --output NAME,TYPE,SIZE,TRAN
```

Parse JSON — find a disk with `"tran": "iscsi"`. Return device path (e.g. `/dev/sdb`). Raise if not found or ambiguous.

---

### `setup_lvm_thin(device)`

Run on `first_host.ip_on(:compute)`.

#### Check if VG already exists

```bash
vgs --reportformat json
```

Parse — if `"pve-iscsi"` VG present, skip creation steps.

#### Create LVM structures

```bash
pvcreate {device}
vgcreate pve-iscsi {device}
lvcreate -l 100%FREE --thinpool data pve-iscsi
```

#### Register LVM-thin in Proxmox

```bash
pvesh create /storage \
  --storage nas-vmdisks \
  --type lvmthin \
  --vgname pve-iscsi \
  --thinpool data \
  --content images,rootdir \
  --shared 1
```

`--shared 1` — all cluster nodes share this VG via the same iSCSI LUN.

Check `storage_exists?("nas-vmdisks")` first.

Update state:
```ruby
state.update_service(:nas, "storage_registered")
state.save!
```

---

### `status`

SSH to `first_host.ip_on(:compute)`:
```bash
pvesh get /storage --output-format json
```

For each storage, check status on all nodes:
```bash
pvesh get /nodes/{node_name}/storage/{storage_id}/status --output-format json
```

Print table: storage ID, type, content types, active status per node.

---

## Commands

### `pcs storage register`

1. Load config, state
2. `first_host = Pcs::Host.where(type: "pve").sort_by(&:hostname).first`
3. `cluster_hosts = Pcs::Host.where(type: "pve")`
4. `nas_host = Pcs::Host.where(type: "truenas").first`
5. `storage = Providers::Proxmox::Storage.new(first_host, cluster_hosts, nas_host, config, state)`
6. Call `storage.register_nfs` then `storage.register_iscsi`

### `pcs storage lvm-setup`

1. Load config, state; build storage provider
2. Call `storage.connect_iscsi_on_nodes` → returns `device`
3. Prompt: "Detected iSCSI LUN at {device}. Proceed with LVM setup? This is destructive."
4. On confirmation (use `TTY::Prompt.new.yes?`): call `storage.setup_lvm_thin(device)`

### `pcs storage status`

Calls `storage.status`, prints table.

---

## Data Dependencies

- Plan 01 complete: cluster quorate, all nodes online
- Plan 02 complete: NAS NFS shares and iSCSI target running
- `nas_host.ip_on(:storage)` set (storage network IP for NFS and iSCSI)
- All PVE nodes have storage network IPs (for iSCSI initiator access)
- `open-iscsi` and `iscsid` running on all PVE nodes

---

## Testing Approach

1. After `pcs storage register`:
   - `pvesh get /storage --output-format json` — expect `nas-iso`, `nas-templates`, `nas-backup`, `nas-iscsi`
   - PVE web UI → Datacenter → Storage — all four visible
2. After `pcs storage lvm-setup`:
   - `pvesh get /storage/nas-vmdisks --output-format json` — expect `"type": "lvmthin"`
   - On each node: `lvs` — expect `data` thin pool in `pve-iscsi` VG
   - Create a test VM with disk on `nas-vmdisks` — should succeed
3. `pcs storage status` shows all 5 storage entries active on all nodes

Do not proceed to Plan 04 until test VM disk creation on `nas-vmdisks` succeeds.
