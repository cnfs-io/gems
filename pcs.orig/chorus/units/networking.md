---
objective: "Promote networks and interfaces to first-class FlatRecord models. Replace hash-blob network data on Site and scattered IP/MAC attributes on Host with a proper relational model."
status: complete
---

# Networking Tier — PCS

## Objective

Promote networks and interfaces to first-class FlatRecord models. Replace the hash-blob network data on Site and the scattered IP/MAC attributes on Host with a proper relational model: Site has_many Networks, Host has_many Interfaces, Interface belongs_to both Host and Network.

**The question this tier answers:** Can PCS model network topology and host connectivity as structured, queryable data rather than embedded hashes and flat columns?

## Background

Current state (post-cleanup):
- **Networks** are a raw hash on Site, loaded from `site.yml` via `after_initialize`. `site.network(:compute)` returns `{ subnet:, gateway:, dns_resolvers: }`. Not a model — can't be queried, associated, or rendered by views.
- **Host** has flat attributes: `mac`, `discovered_ip`, `compute_ip`, `storage_ip`, `preseed_interface`. Adding a third network means adding another `*_ip` column. `mac` is singular but real servers have multiple NICs. `preseed_interface` (e.g., "enp2s0") describes a NIC, not the host.
- **Scan** always targets the compute network. No concept of which interface the scanning host uses.
- **Views** render flat key-value pairs only. No support for displaying associations.

After this tier:
- `Pcs::Network` — FlatRecord model: name, subnet, gateway, dns_resolvers, vlan_id, primary (boolean), site_id
- `Pcs::Interface` — FlatRecord model: name (NIC), mac, ip, host_id, network_id
- `Site has_many :networks` — replaces the `@networks` hash blob and `site.yml` networks section
- `Host has_many :interfaces` — replaces compute_ip, storage_ip, mac, preseed_interface
- `Interface belongs_to :host, belongs_to :network`
- `pcs network scan [name]` — replaces `pcs host scan`, uses the scanning host's interface to determine which network to scan
- `pcs site add` — dynamic network prompting with "add another?" loop
- `pcs host set` — prompts to add interfaces
- View layer supports `has_many` associations in detail views
- `host scan` renamed to `network scan`

## ERD

```
Site ──has_many──> Network (name, subnet, gateway, dns_resolvers, vlan_id, primary)
Site ──has_many──> Host
Host ──has_many──> Interface (name, mac, ip)
Interface ──belongs_to──> Host
Interface ──belongs_to──> Network
```

## Data File Layout

```
sites/
  sg/
    site.yml          # domain, timezone, ssh_key (networks section removed)
    networks.yml      # Network records: [{id, name, subnet, gateway, ...}]
    hosts.yml         # Host records (compute_ip, storage_ip, mac removed)
    interfaces.yml    # Interface records: [{id, name, mac, ip, host_id, network_id}]
```

## Scan Redesign

`pcs network scan [network_name]`:

1. If no arg: find the primary network (or the only network if just one)
2. Verify the CP host has an Interface with an IP in that network's subnet range
3. If not: error "No interface found on [name] network"
4. Scan the network's subnet via nmap
5. Create/update Host records + create Interface records with discovered IP, MAC, and network_id

## Plans

| # | Name | Description | Depends On |
|---|------|-------------|------------|
| 01 | rest-cli-associations | Add `has_many` DSL to RestCli::View. DetailRenderer renders associations as inline tables | — |
| 02 | network-model | Create Pcs::Network FlatRecord model. Migrate site.yml networks hash to networks.yml. Update Site to use has_many :networks | plan-01 |
| 03 | interface-model | Create Pcs::Interface FlatRecord model. Migrate Host IP/MAC/interface attrs to Interface records. Update Host to use has_many :interfaces | plan-02 |
| 04 | site-add-ux | Rewrite `pcs site add` with dynamic network loop ("add another?"). Update `pcs site show` to use view associations | plan-02 |
| 05 | network-scan | Create `pcs network` command namespace. Move scan from `host scan` to `network scan [name]` with interface verification. Update `host set` to prompt for interfaces | plan-03 |
| 06 | consumer-migration | Update Dnsmasq, Netbootxyz, CpCommand, preseed templates, and all other consumers of the old host.compute_ip / site.network(:compute) patterns | plan-03, plan-05 |

## Key Decisions

- **Network.primary** — boolean flag, one per site. Used as default for scan, SSH, management. Set on the first network added (compute).
- **Interface.name** — the Linux NIC name (enp2s0, eth0). Replaces `host.preseed_interface`. May be nil for discovered hosts before configuration.
- **host.discovered_ip stays on Host** — transient bootstrap attribute. When a host is first scanned, we don't yet know the NIC name. An Interface is created with `name: nil` and `network_id` set to the scanned network. The `discovered_ip` on Host is kept for backward compat during the transition but deprecated.
- **Scan creates Interfaces** — `network scan` creates both the Host (if new) and an Interface linking it to the scanned network.
- **RestCli association rendering** — explicit `has_many` declaration in views, not auto-introspection from models. The view controls which associations to display and which columns.
- **No NETWORK_NAMES / NETWORK_FIELDS constants** — these Site constants go away. The data is in Network model records.

## RestCli View Association DSL

```ruby
class SitesView < RestCli::View
  columns       :name, :domain
  detail_fields :name, :domain, :timezone, :ssh_key

  has_many :networks, columns: [:name, :subnet, :gateway, :primary]
end

class HostsView < RestCli::View
  columns       :id, :hostname, :type, :status
  detail_fields :id, :hostname, :type, :role, :arch, :status

  has_many :interfaces, columns: [:name, :network_id, :ip, :mac]
end
```

DetailRenderer checks `self.class._view_associations` and for each, calls `record.send(assoc_name)` then renders as a mini table with a header.

## Completion Criteria

- `Pcs::Network` FlatRecord model with proper attributes and associations
- `Pcs::Interface` FlatRecord model with proper attributes and associations
- No `@networks` hash blob on Site — `site.networks` returns FlatRecord collection
- No `compute_ip`, `storage_ip`, `mac`, `preseed_interface` on Host — data lives on Interface
- `pcs network scan` works with interface verification
- `pcs site add` prompts dynamically for networks
- `pcs site show` renders networks as inline table
- `pcs host show` renders interfaces as inline table
- RestCli::View supports `has_many` association rendering
- All consumers updated (Dnsmasq, Netbootxyz, preseed templates, etc.)
- All specs pass
