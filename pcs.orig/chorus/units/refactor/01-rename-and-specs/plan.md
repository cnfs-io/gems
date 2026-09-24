---
---

# Refactor Plan 01: Rename Inventory -> Device + Characterization Specs

## Goal

Rename the Inventory model/file to Device for consistency with the CLI command namespace, then write characterization specs for all current models. These specs document existing behavior and become the safety net for the FlatRecord refactor in Plan 02.

## Part A: Rename Inventory -> Device

### 1. Rename the model class

- Rename `lib/pcs/models/inventory.rb` -> `lib/pcs/models/device.rb`
- Rename class `Pcs::Models::Inventory` -> `Pcs::Models::Device`
- The class manages a collection of device hashes — the name `Device` is more accurate anyway
- Keep the same public API: `load`, `all`, `find`, `find_by_mac`, `find_by_ip`, `update`, `merge_scan`, `hosts_of_type`, `save!`

### 2. Rename the data file convention

- The model should load from `sites/<site>/devices.yml` instead of `inventory.yml`
- Update the `self.load` method to read `devices.yml`
- Update `save!` to write `devices.yml`

### 3. Update all references

Files that reference `Models::Inventory` or `inventory`:

- `lib/pcs/commands/device/scan.rb` — `Models::Inventory.load` -> `Models::Device.load`
- `lib/pcs/commands/device/get.rb` — same, plus `Models::Inventory::FIELDS` -> `Models::Device::FIELDS`
- `lib/pcs/commands/device/set.rb` — same
- `lib/pcs.rb` or wherever models are required — update require path
- Any service files that reference Inventory

### 4. Migrate spike data

Rename the files in the test fixture project:
- `~/spikes/rws-pcs/me/sites/rok/inventory.yml` -> `devices.yml`
- `~/spikes/rws-pcs/me/sites/sg/inventory.yml` -> `devices.yml`

## Part B: Spec Infrastructure

### 1. Add rspec to development dependencies

```ruby
# pcs.gemspec
spec.add_development_dependency "rspec", "~> 3.0"
```

### 2. Initialize rspec

```bash
cd ~/.local/share/ppm/gems/pcs
bundle exec rspec --init
```

This creates `spec/spec_helper.rb` and `.rspec`.

### 3. Create spec helper with tmpdir project support

```ruby
# spec/spec_helper.rb
# frozen_string_literal: true

require "pcs"
require "fileutils"
require "tmpdir"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.order = :random
end
```

### 4. Create project helper

```ruby
# spec/support/project_helper.rb
# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"

module ProjectHelper
  # Creates a temporary PCS project directory with fixture data.
  # Returns a Pathname to the project root.
  # Caller is responsible for cleanup (use around/after hooks with FileUtils.rm_rf).
  def create_test_project(tmpdir)
    root = Pathname.new(tmpdir)

    # sites/main.yml
    (root / "sites").mkpath
    (root / "sites" / "main.yml").write(YAML.dump(fixture_main_config))

    # sites/sg/
    sg_dir = root / "sites" / "sg"
    sg_dir.mkpath
    (sg_dir / "site.yml").write(YAML.dump(fixture_sg_site))
    (sg_dir / "devices.yml").write(YAML.dump(fixture_sg_devices))
    (sg_dir / "services.yml").write(YAML.dump(fixture_sg_services))

    # sites/rok/
    rok_dir = root / "sites" / "rok"
    rok_dir.mkpath
    (rok_dir / "site.yml").write(YAML.dump(fixture_rok_site))
    (rok_dir / "devices.yml").write(YAML.dump(fixture_rok_devices))
    (rok_dir / "services.yml").write(YAML.dump(fixture_rok_services))

    # .env
    (root / ".env").write("PCS_SITE=sg\n")

    root
  end

  private

  def fixture_main_config
    {
      "defaults" => { "preseed_interface" => "enp2s0" },
      "sites" => {
        "domain" => "me.internal",
        "dns_fallback_resolvers" => ["1.1.1.1", "8.8.8.8"],
        "ip_assignments" => { "cp" => 11, "kvm" => 21, "nas" => 30, "node" => 41 },
        "storage_subnet_offset" => 1
      },
      "services" => {
        "netbootxyz" => { "image" => "docker.io/netbootxyz/netbootxyz" },
        "tailscale" => { "tailnet" => nil },
        "dnsmasq" => nil
      },
      "devices" => {
        "node" => { "proxmox" => nil, "vmware" => nil },
        "nas" => { "truenas" => nil, "synology" => nil },
        "kvm" => { "pikvm" => nil, "glnet" => nil },
        "cp" => { "rpi" => nil }
      }
    }
  end

  def fixture_sg_site
    {
      "domain" => "sg.me.internal",
      "timezone" => "Asia/Singapore",
      "ssh_key" => "~/.ssh/authorized_keys",
      "networks" => {
        "compute" => {
          "subnet" => "172.31.1.0/24",
          "gateway" => "172.31.1.1",
          "dns_resolvers" => ["172.31.1.1", "1.1.1.1", "8.8.8.8"]
        },
        "storage" => {
          "subnet" => "172.31.2.0/24",
          "gateway" => "172.31.2.1",
          "dns_resolvers" => ["172.31.2.1", "1.1.1.1", "8.8.8.8"]
        }
      }
    }
  end

  def fixture_sg_devices
    {
      "devices" => [
        { "id" => 1, "mac" => "7a:45:58:c7:d4:4d", "discovered_ip" => "172.31.1.1",
          "status" => "discovered", "connect_as" => "root" },
        { "id" => 6, "mac" => "70:70:fc:05:2d:69", "discovered_ip" => "172.31.1.112",
          "compute_ip" => "172.31.1.41", "storage_ip" => "172.31.2.41",
          "hostname" => "n1c1", "connect_as" => "root", "type" => "proxmox",
          "role" => "node", "status" => "configured", "arch" => "amd64",
          "preseed_interface" => "enp2s0" },
        { "id" => 8, "mac" => nil, "discovered_ip" => "172.31.1.10",
          "compute_ip" => "172.31.1.10", "hostname" => "ops1",
          "connect_as" => "root", "type" => "rpi", "role" => "cp",
          "status" => "configured", "arch" => "arm64" }
      ]
    }
  end

  def fixture_sg_services
    {
      "tailscale" => { "auth_key" => nil, "status" => "unconfigured" },
      "dnsmasq" => { "status" => "running", "proxy" => false },
      "netboot" => { "status" => "running" }
    }
  end

  def fixture_rok_site
    {
      "domain" => "rok.me.internal",
      "timezone" => "Asia/Singapore",
      "ssh_key" => "~/.ssh/authorized_keys",
      "networks" => {
        "compute" => {
          "subnet" => "172.31.1.0/24",
          "gateway" => "172.31.1.1",
          "dns_resolvers" => ["172.31.1.1", "1.1.1.1", "8.8.8.8"]
        },
        "storage" => {
          "subnet" => "172.31.2.0/24",
          "gateway" => "172.31.2.1",
          "dns_resolvers" => ["172.31.2.1", "1.1.1.1", "8.8.8.8"]
        }
      }
    }
  end

  def fixture_rok_devices
    {
      "devices" => [
        { "id" => 1, "mac" => "88:a2:9e:a1:59:2a", "discovered_ip" => "172.31.1.10",
          "hostname" => "ops1", "connect_as" => "root", "status" => "discovered" }
      ]
    }
  end

  def fixture_rok_services
    {
      "tailscale" => { "auth_key" => nil, "status" => "unconfigured" },
      "dnsmasq" => { "proxy" => true, "status" => "unconfigured" },
      "netboot" => { "status" => "unconfigured" }
    }
  end
end

RSpec.configure do |config|
  config.include ProjectHelper
end
```

## Part C: Model Characterization Specs

### 1. Project spec

```
spec/pcs/project_spec.rb
```

Test:
- `Project.root` finds root by walking up from CWD looking for `sites/main.yml`
- `Project.root` raises `ProjectNotFoundError` when not in a project
- `Project.site` reads PCS_SITE from `.env`
- `Project.site` raises `SiteNotSetError` when not set
- `Project.site_dir` returns correct path for a given site name

Each test should `Dir.chdir` into the tmpdir project.

### 2. Config spec

```
spec/pcs/models/config_spec.rb
```

Test:
- `Config.load` reads `sites/main.yml` and populates all attributes
- Default merging: sites defaults, discovery defaults, provider defaults
- `device_roles` returns `%w[node nas kvm cp]`
- `device_types("node")` returns `%w[proxmox vmware]`
- `service_names` returns the configured service names
- `host_octet(:node, 0)` returns 41, `host_octet(:cp, 0)` returns 11
- `host_octet(:unknown)` raises ArgumentError
- `storage_subnet("172.31.1.0/24")` returns `"172.31.2.0/24"` (with offset 1)
- `storage_gateway("172.31.1.1")` returns `"172.31.2.1"`
- `Config.load` raises `NotFoundError` when `sites/main.yml` is missing

### 3. Device spec (nee Inventory)

```
spec/pcs/models/device_spec.rb
```

Test:
- `Device.load("sg")` loads devices from `sites/sg/devices.yml`
- `all` returns all devices
- `find(6)` returns the configured proxmox device
- `find(999)` returns nil
- `find_by_mac("70:70:fc:05:2d:69")` matches case-insensitively
- `find_by_ip("172.31.1.112")` returns matching device
- `next_id` returns max(ids) + 1
- `update(6, :hostname, "new-name")` changes the field
- `update(6, :id, 99)` raises (id is not in MUTABLE_FIELDS)
- `hosts_of_type("proxmox")` returns devices with type=proxmox
- **merge_scan** — the key domain logic:
  - New device (unknown MAC/IP) gets added with status "discovered"
  - Known MAC with new IP updates `discovered_ip` and `last_seen_at`
  - Known MAC with same IP only updates `last_seen_at`
  - Returns correct `{new:, updated:, unchanged:}` counts
- `save!` writes valid YAML to `devices.yml`
- Loading an empty/missing file returns empty device list

### 4. Site spec

```
spec/pcs/models/site_spec.rb
```

Test:
- `Site.load("sg")` loads from `sites/sg/site.yml`
- `get(:domain)` returns `"sg.me.internal"`
- `get(:timezone)` returns `"Asia/Singapore"`
- `network(:compute)` returns hash with subnet, gateway, dns_resolvers
- `network(:storage)` returns the storage network hash
- `update(:timezone, "UTC")` changes the value
- `update_network(:compute, :gateway, "172.31.1.254")` changes nested value
- `save!` writes valid YAML
- Loading missing file returns empty data without error

### 5. Services spec

```
spec/pcs/models/services_spec.rb
```

Test:
- `Services.load("sg")` loads from `sites/sg/services.yml`
- `all` returns all services as a hash
- `find(:dnsmasq)` returns `{status: "running", proxy: false}`
- `find(:nonexistent)` returns nil
- `update(:dnsmasq, :status, "stopped")` changes the value
- `update(:nonexistent, :status, "x")` raises
- `save!` writes valid YAML

## Execution Notes

- Every spec uses a tmpdir project via `create_test_project`. No test touches real filesystem paths.
- `Dir.chdir(tmpdir)` in a `before` block so `Pcs::Project.root` resolves correctly.
- Use `around(:each)` with `Dir.mktmpdir` for automatic cleanup.
- The fixture data is derived from `~/spikes/rws-pcs/me` but simplified (only 3 sg devices instead of 8, enough to cover configured + discovered states).

## Verification

```bash
cd ~/.local/share/ppm/gems/pcs
bundle install
bundle exec rspec
```

All specs green = Plan 01 complete. The refactor in Plan 02 must keep these specs passing.
