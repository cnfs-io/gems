---
---

# Plan 02: NAS Provisioning

**Tier:** Cluster Formation
**Objective:** Correctness — provision TrueNAS SCALE with the datasets, NFS shares, and iSCSI target that the Proxmox cluster will consume as storage.
**Depends on:** Nothing — can run in parallel with Plan 01.
**Required before:** Plan 03 (Storage Integration)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/cluster-formation/ADR-003-data-model-reference.md` — **read this first**
- `docs/cluster-formation/ADR-001-ssh-cli-over-api-clients.md` — why midclt over SSH
- `lib/pcs/config.rb` — `config.ssh_key_path`
- `lib/pcs/models/host.rb` — `Host.where(type: "truenas")`, `host.ip_on(:compute)`, `host.ip_on(:storage)`
- `lib/pcs/models/state.rb` — `state.update_service(:nas, ...)`, `state.save!`
- `lib/pcs/adapters/ssh.rb` — `SSH.connect`

### What exists vs what needs to be built

**Already exists and should be reused:**
- `Adapters::SSH.connect` — use for all `midclt` SSH calls
- `Pcs::Host` — filter with `.where(type: "truenas")` to find the NAS
- `Pcs::Host` — `.where(type: "pve")` to get PVE node IPs for iSCSI initiator group
- `Pcs::State#update_service` — use `:nas` service key

**Needs to be built:**
- `lib/pcs/providers/truenas/provisioner.rb`
- CLI commands: `pcs nas create`, `pcs nas status`

---

## What This Plan Builds

### New commands
```
pcs nas create                    # provision datasets, NFS shares, iSCSI target
pcs nas status                    # NAS health and share status
```

### New files to create
```
lib/pcs/providers/truenas/provisioner.rb
```

---

## Implementation Spec

### Provider: `Pcs::Providers::TrueNAS::Provisioner`

```ruby
# lib/pcs/providers/truenas/provisioner.rb
def initialize(nas_host, pve_hosts, config, state)
# nas_host: Pcs::Host (type "truenas")
# pve_hosts: Array of Pcs::Host (type "pve") — needed for iSCSI initiator group
```

SSH helper:
```ruby
def ssh(&block)
  Adapters::SSH.connect(host: nas_host.ip_on(:compute), key: config.ssh_key_path, user: "root", &block)
end
```

All `midclt` commands follow: `midclt call <method> <json_args>`. Returns JSON. Parse with `JSON.parse`.

---

### `create_datasets`

Create the parent dataset and children for Proxmox storage:

```bash
midclt call pool.dataset.create '{"name": "tank/proxmox", "type": "FILESYSTEM"}'
midclt call pool.dataset.create '{"name": "tank/proxmox/isos", "type": "FILESYSTEM"}'
midclt call pool.dataset.create '{"name": "tank/proxmox/templates", "type": "FILESYSTEM"}'
midclt call pool.dataset.create '{"name": "tank/proxmox/backups", "type": "FILESYSTEM"}'
```

Check existence first for each:
```bash
midclt call pool.dataset.query '[["name", "=", "tank/proxmox"]]'
```

If result is non-empty array, dataset exists — skip. Idempotent.

---

### `create_nfs_shares`

For each dataset that needs NFS export (isos, templates, backups):

```bash
midclt call sharing.nfs.create '{
  "path": "/mnt/tank/proxmox/isos",
  "comment": "Proxmox ISOs",
  "networks": ["{storage_subnet}"],
  "hosts": [],
  "maproot_user": "root",
  "maproot_group": "wheel"
}'
```

Repeat for templates and backups with appropriate paths and comments.

`storage_subnet` = storage network subnet (e.g. `"172.31.2.0/24"`), derived from the storage network configuration.

Check existence:
```bash
midclt call sharing.nfs.query '[["path", "=", "/mnt/tank/proxmox/isos"]]'
```

Ensure NFS service is enabled:
```bash
midclt call service.start 'nfs'
midclt call service.update 'nfs' '{"enable": true}'
```

---

### `create_iscsi_target`

This creates a zvol, iSCSI extent, target, and initiator group so Proxmox can use it as shared block storage.

#### Step 1: Create zvol for VM disks

```bash
midclt call pool.dataset.create '{
  "name": "tank/proxmox/vmdisks",
  "type": "VOLUME",
  "volsize": {size_in_bytes}
}'
```

`size_in_bytes` — use available pool space minus a reserve. Query available:
```bash
midclt call pool.dataset.query '[["name", "=", "tank"]]' '{"select": ["available"]}'
```

Use 80% of available as a sensible default. Configurable if needed.

#### Step 2: Create iSCSI extent

```bash
midclt call iscsi.extent.create '{
  "name": "vmdisks",
  "type": "DISK",
  "disk": "zvol/tank/proxmox/vmdisks",
  "blocksize": 4096
}'
```

#### Step 3: Create iSCSI portal

```bash
midclt call iscsi.portal.create '{
  "listen": [{"ip": "{nas_storage_ip}", "port": 3260}],
  "comment": "Proxmox storage portal"
}'
```

`nas_storage_ip` = `nas_host.ip_on(:storage)`.

#### Step 4: Create iSCSI initiator group

Build list of PVE node storage IPs for the allowed initiators:

```ruby
pve_storage_ips = pve_hosts.map { |h| h.ip_on(:storage) }.compact
```

```bash
midclt call iscsi.initiator.create '{
  "initiators": [],
  "auth_network": ["{pve_ip_1}/32", "{pve_ip_2}/32", "{pve_ip_3}/32"],
  "comment": "PVE cluster nodes"
}'
```

#### Step 5: Create iSCSI target

```bash
midclt call iscsi.target.create '{
  "name": "{cluster_name}-vmdisks",
  "groups": [{"portal": {portal_id}, "initiator": {initiator_id}}]
}'
```

`portal_id` and `initiator_id` come from the create responses in steps 3 and 4.

#### Step 6: Associate extent to target

```bash
midclt call iscsi.targetextent.create '{
  "target": {target_id},
  "extent": {extent_id},
  "lunid": 0
}'
```

#### Step 7: Enable iSCSI service

```bash
midclt call service.start 'iscsitarget'
midclt call service.update 'iscsitarget' '{"enable": true}'
```

---

### `status`

Query NFS and iSCSI status:

```bash
midclt call sharing.nfs.query
midclt call iscsi.target.query
midclt call iscsi.extent.query
midclt call service.query '[["service", "=", "nfs"]]'
midclt call service.query '[["service", "=", "iscsitarget"]]'
```

Print: datasets, NFS shares (path, status), iSCSI target (name, extent, portal), service status.

Update state after successful provisioning:
```ruby
state.update_service(:nas, "active")
state.save!
```

---

## Commands

### `pcs nas create`

1. Load config, state
2. `nas_host = Pcs::Host.where(type: "truenas").first`
3. `pve_hosts = Pcs::Host.where(type: "pve")`
4. `provisioner = Providers::TrueNAS::Provisioner.new(nas_host, pve_hosts, config, state)`
5. Call `provisioner.create_datasets`
6. Call `provisioner.create_nfs_shares`
7. Call `provisioner.create_iscsi_target`
8. Print summary

### `pcs nas status`

1. Load config
2. `nas_host = Pcs::Host.where(type: "truenas").first`
3. Call `provisioner.status`

---

## Data Dependencies

- TrueNAS reachable via SSH on compute IP
- TrueNAS has a pool named `tank` (or configured pool name)
- PVE hosts have storage network IPs assigned (for iSCSI initiator group)
- `nas_host.ip_on(:storage)` set (for iSCSI portal binding)

---

## Testing Approach

1. After `pcs nas create`:
   - SSH to NAS: `midclt call pool.dataset.query` — expect `tank/proxmox/*` datasets
   - SSH to NAS: `midclt call sharing.nfs.query` — expect 3 NFS shares
   - SSH to NAS: `midclt call iscsi.target.query` — expect target with extent
   - From any PVE node: `showmount -e {nas_storage_ip}` — expect NFS exports listed
   - From any PVE node: `iscsiadm -m discovery -t sendtargets -p {nas_storage_ip}` — expect target IQN
2. `pcs nas status` shows all services active and shares/targets listed

Do not proceed to Plan 03 until both NFS exports and iSCSI target are confirmed reachable from PVE nodes.
