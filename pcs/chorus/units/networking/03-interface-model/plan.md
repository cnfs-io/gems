---
---

# Plan 03 — Interface Model

## Context

Read before starting:
- `lib/pcs/models/host.rb` — Host with flat attrs: mac, discovered_ip, compute_ip, storage_ip, preseed_interface
- `lib/pcs/models/network.rb` — Network model (from plan-02)
- `lib/pcs/views/hosts_view.rb` — current flat view
- `spec/fixtures/project/sites/sg/hosts.yml` — fixture with IP/MAC on host records
- `lib/pcs/models/hosts/pve_host.rb` — STI subclass, may reference host IP attrs
- `lib/pcs/models/hosts/truenas_host.rb` — same
- `lib/pcs/models/hosts/rpi_host.rb` — same

## Goal

Create `Pcs::Interface` as a FlatRecord model. Migrate `mac`, `compute_ip`, `storage_ip`, `preseed_interface` off Host into Interface records. Host gets `has_many :interfaces`. Interface belongs_to both Host and Network.

## Data File Layout

```yaml
# sites/sg/interfaces.yml
- id: "1"
  name: enp2s0
  mac: "70:70:fc:05:2d:69"
  ip: "172.31.1.41"
  host_id: "6"
  network_id: "1"
  site_id: sg
- id: "2"
  name: enp3s0
  mac: "70:70:fc:05:2d:6a"
  ip: "172.31.2.41"
  host_id: "6"
  network_id: "2"
  site_id: sg
```

## Implementation

### Step 1: Create Interface model

Create `lib/pcs/models/interface.rb`:

```ruby
# frozen_string_literal: true

module Pcs
  class Interface < FlatRecord::Base
    source "interfaces"

    attribute :name, :string         # NIC name: enp2s0, eth0 (nil for discovered)
    attribute :mac, :string
    attribute :ip, :string
    attribute :host_id, :string
    attribute :network_id, :string
    attribute :site_id, :string

    belongs_to :host, class_name: "Pcs::Host"
    belongs_to :network, class_name: "Pcs::Network"

    def self.load(site_name = Pcs.site)
      where(site_id: site_name)
    end

    def network_name
      network&.name
    end
  end
end
```

### Step 2: Update Host model

In `lib/pcs/models/host.rb`:

Add:
```ruby
has_many :interfaces, class_name: "Pcs::Interface"
```

Add convenience methods that replace the old flat attributes:

```ruby
# Primary interface = interface on the primary network, or first interface
def primary_interface
  return nil if interfaces.none?
  interfaces.detect { |i| i.network&.primary } || interfaces.first
end

# Convenience accessors via primary interface (migration helpers)
def ip
  primary_interface&.ip
end

def mac
  primary_interface&.mac
end

def interface_name
  primary_interface&.name
end

# Find interface on a specific network
def interface_on(network_name)
  interfaces.detect { |i| i.network&.name == network_name.to_s }
end

def ip_on(network_name)
  interface_on(network_name)&.ip
end
```

Remove from FIELDS/MUTABLE_FIELDS and attribute declarations:
- `compute_ip`
- `storage_ip`
- `preseed_interface`

Keep on Host (for now — transitional):
- `discovered_ip` — still needed for initial scan before interface assignment
- `mac` attribute declaration removed, but the convenience method above provides it

Remove:
- `compute_network` and `storage_network` helper methods (replaced by `interface_on`)
- `has_storage?` (replaced by `interface_on(:storage).present?`)

### Step 3: Update HostsView

In `lib/pcs/views/hosts_view.rb`:

```ruby
class HostsView < RestCli::View
  columns       :id, :hostname, :type, :role, :status
  detail_fields :id, :hostname, :type, :role, :arch, :status,
                :connect_as, :discovered_ip, :preseed_device,
                :discovered_at, :last_seen_at

  has_many :interfaces, columns: [:name, :network_name, :ip, :mac]
end
```

Note: `network_name` uses the delegation method on Interface, not the raw `network_id`.

### Step 4: Update Host::merge_scan

The scan creates both Host and Interface records:

```ruby
def self.merge_scan(site_name, scan_results, network:)
  counts = { new: 0, updated: 0, unchanged: 0 }

  scan_results.each do |result|
    ip = result[:ip]
    mac = result[:mac]

    # Find existing host by MAC (via interfaces) or by discovered_ip
    existing = find_by_mac_via_interface(mac, site_name: site_name) ||
               find_by_ip(ip, site_name: site_name)

    if existing
      existing.update(last_seen_at: Time.now.iso8601)

      # Update or create interface for this network
      iface = existing.interface_on(network.name)
      if iface
        iface.update(ip: ip, mac: mac) if iface.ip != ip
        counts[:unchanged] += 1
      else
        Interface.create(
          mac: mac, ip: ip,
          host_id: existing.id, network_id: network.id,
          site_id: site_name
        )
        counts[:updated] += 1
      end
    else
      host = create(
        discovered_ip: ip,
        site_id: site_name,
        status: "discovered",
        connect_as: "root",
        discovered_at: Time.now.iso8601,
        last_seen_at: Time.now.iso8601
      )
      Interface.create(
        mac: mac, ip: ip,
        host_id: host.id, network_id: network.id,
        site_id: site_name
      )
      counts[:new] += 1
    end
  end

  counts
end

def self.find_by_mac_via_interface(mac, site_name:)
  return nil unless mac
  normalized = mac.downcase
  iface = Interface.load(site_name).detect { |i| i.mac&.downcase == normalized }
  iface&.host
end
```

### Step 5: Create fixture data

Create `spec/fixtures/project/sites/sg/interfaces.yml` with interface records extracted from the current hosts.yml.

Update `spec/fixtures/project/sites/sg/hosts.yml` to remove `mac`, `compute_ip`, `storage_ip`, `preseed_interface` from host records.

Same for `rok/`.

### Step 6: Register model

In `lib/pcs/cli.rb`:
```ruby
require_relative "models/interface"
```

In `lib/pcs/boot.rb`, add `Pcs::Interface.reload!` to `reload_models!`.

## Test Spec

### Interface model specs

```ruby
RSpec.describe Pcs::Interface do
  before { Pcs.boot!(project_dir: fixture_project_path) }

  it "belongs to a host" do
    iface = Pcs::Interface.load("sg").first
    expect(iface.host).to be_a(Pcs::Host)
  end

  it "belongs to a network" do
    iface = Pcs::Interface.load("sg").first
    expect(iface.network).to be_a(Pcs::Network)
  end

  it "delegates network_name" do
    iface = Pcs::Interface.load("sg").first
    expect(iface.network_name).to eq("compute")
  end
end
```

### Host association specs

```ruby
RSpec.describe Pcs::Host do
  before { Pcs.boot!(project_dir: fixture_project_path) }

  it "has many interfaces" do
    host = Pcs::Host.find("6")  # n1c1 in fixture
    expect(host.interfaces.size).to be >= 1
  end

  it "finds primary interface" do
    host = Pcs::Host.find("6")
    expect(host.primary_interface).to be_a(Pcs::Interface)
    expect(host.primary_interface.network.primary).to eq(true)
  end

  it "finds interface on a network" do
    host = Pcs::Host.find("6")
    iface = host.interface_on("compute")
    expect(iface.ip).to eq("172.31.1.41")
  end
end
```

### Verify no old attributes

```bash
grep -r "compute_ip\|storage_ip\|preseed_interface" lib/pcs/models/host.rb  # only discovered_ip remains
grep -r "\.mac " lib/pcs/models/host.rb  # only the delegation method
```

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
```
