---
---

# Plan 04 — Site Add UX

## Context

Read before starting:
- `lib/pcs/commands/sites_command.rb` — current `Add` command with hardcoded two-network flow
- `lib/pcs/models/network.rb` — Network model (from plan-02)
- `lib/pcs/models/site.rb` — Site model (updated in plan-02)
- `lib/pcs/config.rb` — `networking.dns_fallback_resolvers`

## Goal

Rewrite `pcs site add` to use a dynamic network prompting loop. Instead of hardcoding compute + storage, prompt the user to name and configure networks one at a time with "Add another network?" The first network added is automatically marked as primary.

## Implementation

### Step 1: Rewrite SitesCommand::Add

Replace the hardcoded compute/storage flow with:

```ruby
def call(name:, yes: false, **)
  # ... existing validation, project detection, platform detection ...

  net = platform.detect_network(system_cmd)
  fallback = Pcs.config.networking.dns_fallback_resolvers

  # Create site first
  domain = @auto ? "#{name}.#{Pcs::Site.top_level_domain}" :
    prompt.ask("Domain:", default: "#{name}.#{Pcs::Site.top_level_domain}")
  timezone = @auto ? platform.detect_timezone(system_cmd) :
    prompt.select("Timezone:", platform.available_timezones(system_cmd),
                  default: platform.detect_timezone(system_cmd), filter: true)
  ssh_key = @auto ? "~/.ssh/authorized_keys" :
    prompt.ask("SSH key:", default: "~/.ssh/authorized_keys")
  hostname = @auto ? "ops1" : prompt.ask("Hostname:", default: "ops1")

  site_dir.mkpath

  site = Pcs::Site.new(name: name, domain: domain, timezone: timezone, ssh_key: ssh_key)
  site.save!

  Pcs::Site.reload!
  Pcs::Host.reload!
  Pcs::Network.reload!
  Pcs::Interface.reload!

  # Network loop
  network_index = 0
  last_subnet = net[:compute_subnet]

  loop do
    if network_index == 0
      default_name = "compute"
      default_subnet = last_subnet
    else
      default_name = prompt_next_network_name(network_index)
      default_subnet = increment_subnet_octet(last_subnet)
    end

    if @auto
      # Auto mode: create compute only
      break if network_index > 0
      net_name = default_name
      subnet = default_subnet
      gateway = gateway_for(subnet)
      dns = [gateway] + fallback
    else
      net_name = prompt.ask("Network name:", default: default_name)
      subnet = prompt.ask("#{net_name} subnet:", default: default_subnet)
      gateway = prompt.ask("#{net_name} gateway:", default: gateway_for(subnet))
      dns = prompt.ask("#{net_name} DNS resolvers (comma-separated):",
                       default: ([gateway] + fallback).join(", "))
                   .split(",").map(&:strip)
    end

    Pcs::Network.create(
      name: net_name,
      subnet: subnet,
      gateway: gateway,
      dns_resolvers: dns,
      primary: network_index == 0,
      site_id: name
    )

    last_subnet = subnet
    network_index += 1

    break if @auto
    break unless prompt.yes?("Add another network?", default: false)
  end

  # Create CP host + interface on primary network
  primary_net = Pcs::Network.primary(name)
  host = Pcs::Host.create(
    discovered_ip: net[:current_ip],
    site_id: name,
    status: "discovered",
    connect_as: "root",
    hostname: hostname,
    discovered_at: Time.now.iso8601,
    last_seen_at: Time.now.iso8601
  )
  Pcs::Interface.create(
    mac: net[:mac],
    ip: net[:current_ip],
    host_id: host.id,
    network_id: primary_net.id,
    site_id: name
  )

  # Set active site if none set
  # ... existing .env logic ...
end

private

def increment_subnet_octet(subnet)
  parts = subnet.split("/")
  octets = parts[0].split(".")
  octets[2] = (octets[2].to_i + 1).to_s
  "#{octets.join(".")}/#{parts[1]}"
end

def prompt_next_network_name(index)
  %w[compute storage management][index] || "network#{index}"
end
```

### Step 2: Update SitesCommand::Set

Replace `NETWORK_NAMES.each` with `site.networks.each`, and add "Add another network?" at the end:

```ruby
site.networks.each do |net|
  subnet = prompt.ask("#{net.name.capitalize} subnet:", default: net.subnet)
  gateway = prompt.ask("#{net.name.capitalize} gateway:", default: net.gateway)
  dns = prompt.ask("#{net.name.capitalize} DNS (comma-separated):",
                   default: net.dns_resolvers&.join(", "))
               .split(",").map(&:strip)

  net.update(subnet: subnet, gateway: gateway, dns_resolvers: dns)
end

if prompt.yes?("Add another network?", default: false)
  # Similar prompting loop as Add
end
```

### Step 3: Remove derive_storage_* from Site

These class methods assumed exactly two networks with a fixed offset. Remove them — the dynamic loop handles subnet defaulting via `increment_subnet_octet`.

Also remove `storage_subnet_offset` from `Pcs::NetworkingSettings` in `config.rb` — it's no longer needed.

### Step 4: Update `pcs site show`

Already handled in plan-02 — the view's `has_many :networks` renders the association. Verify it works end-to-end.

### Step 5: Auto mode (-y flag)

When `--yes` is passed, create only the primary (compute) network with auto-detected values. This keeps the non-interactive path simple while the interactive path is flexible.

## Test Spec

```ruby
RSpec.describe "pcs site add" do
  it "creates networks via loop" do
    # After adding a site with two networks:
    site = Pcs::Site.load("test")
    expect(site.networks.size).to eq(2)
    expect(site.networks.first.primary).to eq(true)
    expect(site.networks.first.name).to eq("compute")
  end

  it "creates CP host with interface on primary network" do
    site = Pcs::Site.load("test")
    cp = Pcs::Host.load("test").detect { |h| h.hostname == "ops1" }
    iface = cp.interfaces.first
    expect(iface.network).to eq(site.primary_network)
  end
end
```

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
# Manual: run `pcs site add test` interactively, verify network prompting loop
```
