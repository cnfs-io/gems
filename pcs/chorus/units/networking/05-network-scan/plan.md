---
---

# Plan 05 — Network Scan

## Context

Read before starting:
- `lib/pcs/commands/hosts_command.rb` — current `Scan` command under `pcs host scan`
- `lib/pcs/models/host.rb` — `merge_scan` (updated in plan-03 to create interfaces)
- `lib/pcs/models/network.rb` — Network model with `contains_ip?`
- `lib/pcs/models/interface.rb` — Interface model
- `lib/pcs/adapters/nmap.rb` — nmap adapter
- `lib/pcs/cli.rb` — command registration

## Goal

Create `pcs network` command namespace. Move scan from `pcs host scan` to `pcs network scan [name]`. The scan verifies the CP host has an interface on the target network before scanning. Add `pcs network list` and `pcs network show`. Update `pcs host set` to prompt for interface creation.

## Implementation

### Step 1: Create NetworksCommand

Create `lib/pcs/commands/networks_command.rb`:

```ruby
module Pcs
  class NetworksCommand < RestCli::Command

    class List < self
      desc "List networks for the current site"

      def call(**options)
        networks = Pcs::Network.load
        if networks.none?
          puts "No networks. Run 'pcs site add' to create a site with networks."
          return
        end
        view.list(networks.to_a, **view_options(options))
      end
    end

    class Show < self
      desc "Show network details"
      argument :name, required: true, desc: "Network name"

      def call(name:, **options)
        network = Pcs::Network.find_by_name(name)
        unless network
          $stderr.puts "Error: Network '#{name}' not found."
          exit 1
        end
        view.show(network, **view_options(options))
      end
    end

    class Scan < self
      desc "Scan a network for hosts"
      argument :name, required: false, desc: "Network name (default: primary)"

      def call(name: nil, **)
        site_name = Pcs.site

        # Resolve target network
        network = if name
                    Pcs::Network.find_by_name(name, site_name: site_name)
                  else
                    Pcs::Network.primary(site_name)
                  end

        unless network
          target = name || "primary"
          $stderr.puts "Error: Network '#{target}' not found."
          exit 1
        end

        # Verify CP host has an interface on this network
        cp_host = Pcs::Host.load(site_name).detect { |h| h.role == "cp" }
        unless cp_host
          $stderr.puts "Error: No control plane host found."
          exit 1
        end

        cp_iface = cp_host.interface_on(network.name)
        unless cp_iface
          $stderr.puts "Error: Control plane host has no interface on '#{network.name}' network."
          $stderr.puts "  Configure an interface first with 'pcs host set #{cp_host.id}'."
          exit 1
        end

        # Also verify the CP's interface IP is actually in the network's subnet
        unless network.contains_ip?(cp_iface.ip)
          $stderr.puts "Error: CP interface IP #{cp_iface.ip} is not in #{network.name} subnet #{network.subnet}."
          exit 1
        end

        puts "Scanning #{network.name} (#{network.subnet})..."

        nmap = Adapters::Nmap.new
        results = nmap.scan(network.subnet)

        counts = Pcs::Host.merge_scan(site_name, results, network: network)

        puts "  New: #{counts[:new]}, Updated: #{counts[:updated]}, Unchanged: #{counts[:unchanged]}"
        puts

        hosts = Pcs::Host.load(site_name)
        if hosts.none?
          puts "No hosts found."
          return
        end

        host_view = Pcs::HostsView.new
        host_view.list(hosts.to_a)
      end
    end
  end
end
```

### Step 2: Create NetworksView

Create `lib/pcs/views/networks_view.rb`:

```ruby
module Pcs
  class NetworksView < RestCli::View
    columns       :name, :subnet, :gateway, :primary
    detail_fields :name, :subnet, :gateway, :dns_resolvers, :vlan_id, :primary

    has_many :interfaces, columns: [:name, :ip, :mac, :host_id]
  end
end
```

Note: `network show compute` will display the network details plus all interfaces on that network. This is useful for seeing which hosts are connected.

For this to work, Network needs:
```ruby
has_many :interfaces, class_name: "Pcs::Interface"
```

### Step 3: Register commands in CLI

In `lib/pcs/cli.rb`:

```ruby
require_relative "commands/networks_command"

# Networks
register "network list",     NetworksCommand::List
register "network show",     NetworksCommand::Show
register "network scan",     NetworksCommand::Scan
```

### Step 4: Remove old host scan

Remove `Scan` from `HostsCommand`. Remove `register "host scan"` from CLI.

If desired, keep `pcs host scan` as an alias that prints a deprecation notice and delegates to `pcs network scan`. Or just remove it cleanly — the tier is a breaking change anyway.

### Step 5: Update HostsCommand::Set to prompt for interfaces

In the `interactive_configure` method, after the existing prompts (role, type, hostname, arch), add:

```ruby
# Interface prompting
if prompt.yes?("Add interface?", default: false)
  networks = Pcs::Network.load
  network_choices = networks.map { |n| { name: "#{n.name} (#{n.subnet})", value: n } }

  loop do
    net = prompt.select("Network:", network_choices)
    iface_name = prompt.ask("Interface name (e.g., enp2s0):", default: nil)
    ip = prompt.ask("IP address:", default: nil)
    mac = prompt.ask("MAC address:", default: host.primary_interface&.mac)

    Pcs::Interface.create(
      name: iface_name,
      mac: mac,
      ip: ip,
      host_id: host.id,
      network_id: net.id,
      site_id: Pcs.site
    )

    break unless prompt.yes?("Add another interface?", default: false)
  end
end
```

### Step 6: Add Network has_many :interfaces

In `lib/pcs/models/network.rb`:
```ruby
has_many :interfaces, class_name: "Pcs::Interface"
```

## Test Spec

### NetworksCommand specs

```ruby
RSpec.describe Pcs::NetworksCommand::Scan do
  it "scans the primary network by default"
  it "scans a named network when specified"
  it "errors when CP has no interface on target network"
  it "errors when named network does not exist"
end
```

### Verify command tree

```bash
pcs network list
pcs network show compute
pcs network scan
pcs network scan storage
```

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
grep -r "host scan" lib/     # should be gone (or deprecated alias only)
```
