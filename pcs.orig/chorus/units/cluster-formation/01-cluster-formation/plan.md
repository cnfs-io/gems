---
---

# Plan 01: Cluster Formation

**Tier:** Cluster Formation
**Objective:** Correctness — form a working Proxmox VE cluster from pre-provisioned nodes, verify quorum, and create a scoped API token for subsequent automation.
**Depends on:** Nothing — this is the starting point. All PVE nodes are installed and reachable via SSH.
**Required before:** Plan 03 (Storage Integration)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/cluster-formation/ADR-003-data-model-reference.md` — **read this first** — authoritative reference for all models
- `lib/pcs/config.rb` — `config.ssh_key_path`, `config.defaults[:root_password]`
- `lib/pcs/models/host.rb` — Host model with STI, `host.ip_on(:compute)`, `host.fqdn`
- `lib/pcs/models/state.rb` — `state.update_service`, `state.save!`
- `lib/pcs/adapters/ssh.rb` — `SSH.connect`, `SSH.port_open?`

### What exists vs what needs to be built

**Already exists and should be reused:**
- `Adapters::SSH.connect` — use for all `pvesh` SSH calls
- `Adapters::SSH.port_open?` — use for polling after cluster join restarts `pve-cluster`
- `Pcs::Host` — filter with `.where(type: "pve")` or iterate `.all`
- `Pcs::State#update_service` — use `:cluster` service key

**Needs to be built:**
- `lib/pcs/providers/proxmox/cluster.rb`
- CLI commands: `pcs cluster create`, `pcs cluster join`, `pcs cluster token`, `pcs cluster status`

**Needs updating:**
- `lib/pcs/commands/clusters_command.rb` — add new subcommands alongside existing `Install`
- `lib/pcs/cli.rb` — register new commands

---

## What This Plan Builds

### New commands
```
pcs cluster create              # form cluster on first node
pcs cluster join [--node NAME]  # join remaining nodes
pcs cluster token               # create automation API token
pcs cluster status              # print cluster health
```

### New files to create
```
lib/pcs/providers/proxmox/cluster.rb
```

Commands are added to existing `clusters_command.rb`.

---

## Implementation Spec

### Provider: `Pcs::Providers::Proxmox::Cluster`

```ruby
# lib/pcs/providers/proxmox/cluster.rb
def initialize(config, state)
```

SSH helper:
```ruby
def ssh(ip, &block)
  Adapters::SSH.connect(host: ip, key: config.ssh_key_path, user: "root", &block)
end
```

All `pvesh` commands return JSON when `--output-format json` is passed. Parse with `JSON.parse(result)`.

---

### `create(first_host)`

`first_host` is a `Pcs::Host` (type `"pve"`).

SSH to `first_host.ip_on(:compute)`.

#### Step 1: Check if cluster already exists

```bash
pvesh get /cluster/status --output-format json
```

Parse JSON. If any entry has `"type" => "cluster"`, cluster exists — log and return. Idempotent.

#### Step 2: Create cluster

Cluster name: use the site name or a `cluster_name` key from config if present.

```bash
pvesh create /cluster/config \
  --clustername {cluster_name} \
  --link0 address={first_host.ip_on(:compute)}
```

#### Step 3: Verify

```bash
pvesh get /cluster/status --output-format json
```

Confirm entry with `"type" => "cluster"` and correct name. Update state:
```ruby
state.update_service(:cluster, "created", node: first_host.hostname)
state.save!
```

---

### `join(joining_host, first_host)`

Both are `Pcs::Host` objects.

#### Step 1: Check if already joined

SSH to `joining_host.ip_on(:compute)`:
```bash
pvesh get /cluster/status --output-format json
```

If cluster entry present with correct name, already joined — return. Idempotent.

#### Step 2: Get fingerprint from first node

SSH to `first_host.ip_on(:compute)`:
```bash
pvesh get /cluster/config/join --output-format json \
  --address {first_host.ip_on(:compute)}
```

Extract `"fingerprint"` from response.

#### Step 3: Issue join from joining node

SSH to `joining_host.ip_on(:compute)`:
```bash
pvesh create /cluster/config/join \
  --hostname {first_host.ip_on(:compute)} \
  --password {config.defaults[:root_password]} \
  --fingerprint {fingerprint} \
  --link0 address={joining_host.ip_on(:compute)}
```

#### Step 4: Wait for rejoin

After join, `pve-cluster` restarts on the joining node. Poll port 8006:
```ruby
Adapters::SSH.port_open?(joining_host.ip_on(:compute), 8006)
```

Poll every 10s, up to 18 attempts (3 minutes).

#### Step 5: Verify from first node

SSH to `first_host.ip_on(:compute)`:
```bash
pvesh get /cluster/status --output-format json
```

Confirm `joining_host.hostname` appears with `"online" => 1`.

---

### `join_all(first_host, peer_hosts)`

`peer_hosts` is all PVE hosts except the first.

Call `join(peer, first_host)` for each peer sequentially. Sleep 10s between joins. After all joins, verify quorum:

SSH to `first_host.ip_on(:compute)`:
```bash
pvesh get /cluster/status --output-format json
```

Confirm `"quorate" => 1`. Update state:
```ruby
state.update_service(:cluster, "active")
state.save!
```

---

### `create_token(first_host)`

SSH to `first_host.ip_on(:compute)`.

#### Step 1: Create automation user

```bash
pveum user add automation@pve --comment "pcs automation"
```

Ignore error if already exists.

#### Step 2: Grant Administrator role

```bash
pveum acl modify / --user automation@pve --role Administrator --propagate 1
```

#### Step 3: Create token

```bash
pveum user token add automation@pve bootstrap \
  --privsep 0 \
  --output-format json
```

Parse JSON, extract `"value"` (token secret — shown only once).

#### Step 4: Persist

Store in state under a `proxmox_token` key:
```ruby
# Extend State if needed to support token storage
state.set(:proxmox_token, { id: "automation@pve!bootstrap", secret: token_value })
state.save!
```

Print token ID and secret to terminal.

---

### `status(any_host)`

SSH to `any_host.ip_on(:compute)`:

```bash
pvesh get /cluster/status --output-format json
pvesh get /nodes --output-format json
```

Format and print: cluster name, quorate status, node count, per-node online/offline.

---

## Commands

### `pcs cluster create`

1. Load config, state
2. Find PVE hosts: `Pcs::Host.where(type: "pve")` (or equivalent)
3. Sort by hostname — first alphabetically is `first_host`
4. Call `Cluster.new(config, state).create(first_host)`

### `pcs cluster join [--node NAME]`

1. Load config, state
2. `pve_hosts` sorted by hostname; `first_host = pve_hosts.first`
3. Without `--node`: `cluster.join_all(first_host, pve_hosts[1..])`
4. With `--node`: find host by name, `cluster.join(host, first_host)`

### `pcs cluster token`

1. Load config, state
2. `first_host = pve_hosts.first`
3. Call `cluster.create_token(first_host)`

### `pcs cluster status`

1. `first_host = pve_hosts.first`
2. Call `cluster.status(first_host)`

---

## Data Dependencies

- All PVE nodes reachable via SSH on their compute IP
- `config.defaults[:root_password]` set (used for cluster join handshake)
- PVE hosts defined in IPAM/Host model with type `"pve"` and compute IPs assigned

---

## Testing Approach

1. After `pcs cluster create`: web UI at `https://{first_node_ip}:8006` → Datacenter shows cluster name
2. After `pcs cluster join`: `pvesh get /cluster/status` from first node — all nodes online, `quorate: 1`
3. After `pcs cluster token`: `states/{site}/state.yml` contains `proxmox_token` section
4. Verify token works: `pvesh get /version --apitoken automation@pve\!bootstrap={secret}`
5. `pcs cluster status` prints all nodes online

Do not proceed to Plan 03 until quorum is confirmed with all nodes.
