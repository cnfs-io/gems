---
---

# Plan 06 — Consumer Migration

## Context

Read before starting:
- `lib/pcs/service/dnsmasq.rb` — references `site.network(:compute)[:subnet]`, `cp_device.compute_ip`
- `lib/pcs/service/netbootxyz.rb` — references `host.compute_ip`, `host.mac`, `host.preseed_interface`, `host.storage_ip`, `site.network(:compute)`
- `lib/pcs/service/control_plane.rb` — applies static IPs
- `lib/pcs/commands/cp_command.rb` — references host IPs and site networks
- `lib/pcs/commands/clusters_command.rb` — references host attributes
- `lib/pcs/models/hosts/pve_host.rb` — STI subclass, may reference IP attrs
- `lib/pcs/models/hosts/truenas_host.rb` — same
- `lib/pcs/models/hosts/rpi_host.rb` — same
- `lib/pcs/models/hosts/pikvm_host.rb` — same
- `lib/pcs/templates/` — ERB templates that reference host attributes
- `lib/pcs/models/state.rb` — `default_services` still references network/tunnel verticals

## Goal

Update every consumer of the old patterns to use the new Network/Interface models. This is the "long tail" plan — mechanical find-and-replace across the codebase.

## Migration Patterns

### Pattern 1: site.network(:compute) hash access -> model access

```ruby
# Before:
compute = site.network(:compute)
subnet = compute[:subnet]
gateway = compute[:gateway]
dns = compute[:dns_resolvers]

# After:
compute = site.network(:compute)   # returns Pcs::Network instance
subnet = compute.subnet
gateway = compute.gateway
dns = compute.dns_resolvers
```

`site.network(:compute)` still works (convenience method on Site from plan-02) but now returns a Network model instance. All `[:key]` hash access becomes `.key` method access.

### Pattern 2: host.compute_ip -> host.ip_on(:compute) or host.ip

```ruby
# Before:
ops_ip = cp_device.compute_ip || cp_device.discovered_ip

# After:
ops_ip = cp_device.ip || cp_device.discovered_ip
# (host.ip delegates to primary_interface.ip)

# Or when you need a specific network:
storage_ip = host.ip_on(:storage)
```

### Pattern 3: host.mac -> host.mac (delegation)

No change needed for most callers — `host.mac` now delegates to `primary_interface.mac`. But callers that set `host.mac` need to create/update an Interface instead.

### Pattern 4: host.preseed_interface -> host.interface_name

```ruby
# Before:
interface = dev.preseed_interface || "enp1s0"

# After:
interface = dev.interface_name || "enp1s0"
```

### Pattern 5: host.storage_ip -> host.ip_on(:storage)

```ruby
# Before:
has_storage = !host.storage_ip.nil?

# After:
has_storage = host.interface_on(:storage).present?
```

## Implementation

### Step 1: Update Service::Dnsmasq

In `write_config`:
```ruby
# site.network(:compute) now returns Network model
compute = site.network(:compute)
compute_subnet = compute.subnet
gateway = compute.gateway

# CP host IP via delegation
ops_ip = cp_device.ip || cp_device.discovered_ip
```

### Step 2: Update Service::Netbootxyz

In `generate_pxe_files`:
- `dev.mac` -> works (delegation)
- `dev.compute_ip || dev.discovered_ip` -> `dev.ip || dev.discovered_ip`
- `dev.preseed_interface` -> `dev.interface_name`
- `dev.arch` -> unchanged (stays on Host)

In `generate_install_files`:
- `site.network(:compute)` -> returns Network model, use `.gateway`, `.dns_resolvers`, `.subnet`
- `host.compute_ip` -> `host.ip`
- `host.storage_ip` -> `host.ip_on(:storage)`
- `host.preseed_interface` -> `host.interface_name`

In the peers list:
```ruby
# Before:
all_peers = (Pcs::Host.hosts_of_type("proxmox") + Pcs::Host.hosts_of_type("truenas"))
              .select { |d| d.hostname && d.compute_ip }

# After:
all_peers = (Pcs::Host.hosts_of_type("proxmox") + Pcs::Host.hosts_of_type("truenas"))
              .select { |d| d.hostname && d.ip }
```

### Step 3: Update Service::ControlPlane

`apply_static_ip` receives IP/gateway/dns as parameters, so the method itself may not need changes. But its callers (CpCommand) need to source these from Network/Interface models.

### Step 4: Update CpCommand

In `cp_command.rb`, update any references to site networks and host IPs to use the new model patterns.

### Step 5: Update STI host subclasses

Check each file in `lib/pcs/models/hosts/`:
- `pve_host.rb`
- `truenas_host.rb`
- `pikvm_host.rb`
- `rpi_host.rb`

Replace any `compute_ip`, `storage_ip`, `mac`, `preseed_interface` references.

### Step 6: Update ERB templates

Check all templates in `lib/pcs/templates/`:
- `netboot/preseed.cfg.erb` — likely references host IPs
- `netboot/mac-boot.ipxe.erb` — references MAC
- `netboot/pcs-menu.ipxe.erb` — references IPs
- `netboot/post-install.sh.erb`

Template variables are set in `generate_install_files` and `generate_pxe_files`, so the templates themselves may not need changes if the variable names stay the same. Verify.

### Step 7: Update State model

In `lib/pcs/models/state.rb`, update `default_services`:
```ruby
# Before:
def default_services
  { network: ..., cluster: ..., nas: ..., tunnel: ... }
end

# After:
def default_services
  { cluster: { status: "unconfigured" }, nas: { status: "unconfigured" } }
end
```

Remove the network and tunnel entries.

### Step 8: Update Host base class

Remove deprecated methods from `lib/pcs/models/host.rb`:
- `compute_network` method
- `storage_network` method
- `has_storage?` method

Also remove `discovered_ip` from Host if all callers now use Interface. Or keep it as a transitional attribute if scan still writes it — evaluate after wiring everything up.

### Step 9: Full grep audit

```bash
grep -rn "compute_ip\|storage_ip\|preseed_interface" lib/ spec/ --include="*.rb" --include="*.erb"
grep -rn "\[:subnet\]\|\[:gateway\]\|\[:dns_resolvers\]" lib/ spec/
grep -rn "NETWORK_NAMES\|NETWORK_FIELDS" lib/ spec/
```

Fix every hit.

## Test Spec

- All existing specs pass with updated fixtures
- Preseed generation produces correct IPs sourced from Interface records
- PXE file generation uses correct MACs from Interface records
- Dnsmasq config writes correct subnet/gateway from Network model

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
grep -rn "compute_ip\|storage_ip" lib/pcs/models/host.rb   # only discovered_ip if kept
grep -rn "\[:subnet\]\|\[:gateway\]" lib/                    # should be empty
```
