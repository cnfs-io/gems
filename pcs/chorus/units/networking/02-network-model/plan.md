---
---

# Plan 02 — Network Model

## Context

Read before starting:
- `lib/pcs/models/site.rb` — current Site model with `@networks` hash blob, `load_site_yml`, `save!`
- `lib/pcs/views/sites_view.rb` — current flat view, needs `has_many :networks`
- `lib/pcs/commands/sites_command.rb` — Add, Show, Set commands reference `NETWORK_NAMES`, `NETWORK_FIELDS`
- `spec/fixtures/project/sites/sg/site.yml` — current fixture with embedded networks hash
- `spec/fixtures/project/sites/rok/site.yml` — same
- `lib/pcs/config.rb` — `storage_subnet_offset` and `derive_storage_*` methods on Site
- `~/.local/share/ppm/gems/flat_record/lib/flat_record/associations.rb` — has_many implementation

## Goal

Create `Pcs::Network` as a FlatRecord model. Migrate the networks hash from `site.yml` into `networks.yml`. Site gets `has_many :networks` and the `@networks` hash blob, `load_site_yml` network parsing, `NETWORK_NAMES`, `NETWORK_FIELDS`, `network()`, `update_network()` all go away.

## Data File Layout

```yaml
# sites/sg/networks.yml
- id: "1"
  name: compute
  subnet: "172.31.1.0/24"
  gateway: "172.31.1.1"
  dns_resolvers:
    - "172.31.1.1"
    - "1.1.1.1"
    - "8.8.8.8"
  primary: true
  site_id: sg
- id: "2"
  name: storage
  subnet: "172.31.2.0/24"
  gateway: "172.31.2.1"
  dns_resolvers:
    - "172.31.2.1"
    - "1.1.1.1"
    - "8.8.8.8"
  primary: false
  site_id: sg
```

## Implementation

### Step 1: Create Network model

Create `lib/pcs/models/network.rb`:

```ruby
# frozen_string_literal: true

module Pcs
  class Network < FlatRecord::Base
    source "networks"

    attribute :name, :string
    attribute :subnet, :string
    attribute :gateway, :string
    attribute :dns_resolvers                # Array
    attribute :vlan_id, :integer
    attribute :primary, :boolean, default: false
    attribute :site_id, :string

    belongs_to :site, class_name: "Pcs::Site"

    def self.load(site_name = Pcs.site)
      where(site_id: site_name)
    end

    def self.primary(site_name = Pcs.site)
      find_by(site_id: site_name, primary: true)
    end

    def self.find_by_name(name, site_name: Pcs.site)
      find_by(name: name.to_s, site_id: site_name)
    end

    # Check if an IP address falls within this network's subnet
    def contains_ip?(ip)
      require "ipaddr"
      IPAddr.new(subnet).include?(ip)
    end
  end
end
```

### Step 2: Update Site model

In `lib/pcs/models/site.rb`:

- Add `has_many :networks, class_name: "Pcs::Network"`
- Remove: `NETWORK_NAMES`, `NETWORK_FIELDS` constants
- Remove: `network()`, `update_network()`, `get()` methods (the `:networks` branch)
- Remove: `@networks` instance variable from `load_site_yml` and `save!`
- Remove: `derive_storage_subnet`, `derive_storage_gateway` class methods (move to Network or inline in command)
- Keep the `after_initialize :load_site_yml` but strip the networks parsing from it
- The `save!` method should only write domain, timezone, ssh_key to `site.yml`

Add a convenience method:
```ruby
def network(name)
  networks.find { |n| n.name == name.to_s }
end

def primary_network
  networks.find(&:primary)
end
```

These provide a migration path for existing callers like `site.network(:compute)` — but now they return a Network model instance, not a hash. Callers that did `site.network(:compute)[:subnet]` become `site.network(:compute).subnet`.

### Step 3: Update SitesView

In `lib/pcs/views/sites_view.rb`:

```ruby
class SitesView < RestCli::View
  columns       :name, :domain
  detail_fields :name, :domain, :timezone, :ssh_key

  has_many :networks, columns: [:name, :subnet, :gateway, :primary]
end
```

### Step 4: Update SitesCommand::Show

Replace the manual network iteration with the view:

```ruby
class Show < self
  desc "Show site information"
  argument :name, required: true, desc: "Site name"

  def call(name:, **options)
    site = Pcs::Site.load(name)
    view.show(site, **view_options(options))
  end
end
```

The view's `has_many :networks` handles the association rendering.

### Step 5: Update SitesCommand::Set

Replace `NETWORK_NAMES.each` loop with iterating `site.networks`:

```ruby
site.networks.each do |net|
  subnet = prompt.ask("#{net.name.capitalize} subnet:", default: net.subnet)
  gateway = prompt.ask("#{net.name.capitalize} gateway:", default: net.gateway)
  dns = prompt.ask("#{net.name.capitalize} DNS (comma-separated):",
                   default: net.dns_resolvers&.join(", "))
               .split(",").map(&:strip)

  net.update(subnet: subnet, gateway: gateway, dns_resolvers: dns)
end
```

### Step 6: Create fixture data

Create `spec/fixtures/project/sites/sg/networks.yml` and `spec/fixtures/project/sites/rok/networks.yml` with the data currently embedded in `site.yml`.

Remove the `networks:` section from both `site.yml` fixtures.

### Step 7: Register model in cli.rb and boot.rb

In `lib/pcs/cli.rb`, add:
```ruby
require_relative "models/network"
```

In `lib/pcs/boot.rb`, add `Pcs::Network.reload!` to `reload_models!`.

### Step 8: Update `pcs new` scaffold

If the scaffold template creates `site.yml` with networks, update it to create `networks.yml` instead.

## Test Spec

### Network model specs

```ruby
RSpec.describe Pcs::Network do
  before { Pcs.boot!(project_dir: fixture_project_path) }

  it "loads networks for a site" do
    networks = Pcs::Network.load("sg")
    expect(networks.size).to eq(2)
  end

  it "finds primary network" do
    primary = Pcs::Network.primary("sg")
    expect(primary.name).to eq("compute")
    expect(primary.primary).to eq(true)
  end

  it "finds by name" do
    net = Pcs::Network.find_by_name("storage", site_name: "sg")
    expect(net.subnet).to eq("172.31.2.0/24")
  end

  it "checks IP containment" do
    net = Pcs::Network.find_by_name("compute", site_name: "sg")
    expect(net.contains_ip?("172.31.1.50")).to eq(true)
    expect(net.contains_ip?("172.31.2.50")).to eq(false)
  end
end
```

### Site association specs

```ruby
RSpec.describe Pcs::Site do
  before { Pcs.boot!(project_dir: fixture_project_path) }

  it "has many networks" do
    site = Pcs::Site.load("sg")
    expect(site.networks.size).to eq(2)
    expect(site.networks.first).to be_a(Pcs::Network)
  end

  it "finds network by name" do
    site = Pcs::Site.load("sg")
    compute = site.network(:compute)
    expect(compute.subnet).to eq("172.31.1.0/24")
  end

  it "finds primary network" do
    site = Pcs::Site.load("sg")
    expect(site.primary_network.name).to eq("compute")
  end
end
```

### Verify no hash access patterns

```bash
grep -r "site\.network.*\[:" lib/     # should return empty — no more hash access
grep -r "NETWORK_NAMES\|NETWORK_FIELDS" lib/  # should return empty
```

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
grep -r "\[:subnet\]\|\[:gateway\]\|\[:dns_resolvers\]" lib/
```
