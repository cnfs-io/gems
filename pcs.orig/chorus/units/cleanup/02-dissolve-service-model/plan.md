---
---

# Plan 02 — Dissolve Service Model

## Context

Read before starting:
- `lib/pcs/models/service.rb` — the FlatRecord model to delete
- `lib/pcs/views/services_view.rb` — RestCli view to delete
- `lib/pcs/commands/services_command.rb` — currently uses Service model for CRUD
- `lib/pcs/services/netboot_service.rb` — calls `Pcs::Service.definition("netbootxyz")` for config
- `lib/pcs/services/dnsmasq_service.rb` — calls `Pcs::Service.find_by_name("dnsmasq")` for proxy flag
- `lib/pcs/cli.rb` — requires models/service, views
- `lib/pcs/boot.rb` — `reload_models!` references Service, `pcs.yml.erb` template has services section
- `lib/pcs/config.rb` — will need new `service` config block
- `spec/pcs/models/services_spec.rb` — model spec to delete
- `spec/pcs/views/services_view_spec.rb` — view spec to delete
- `spec/fixtures/project/data/services.yml` — fixture to delete
- `spec/fixtures/project/sites/*/services.yml` — fixtures to delete

## Implementation

### Step 1: Add service config DSL to Pcs::Config

In `lib/pcs/config.rb`, add service configuration classes and a `service` accessor:

```ruby
class DnsmasqSettings
  attr_accessor :proxy

  def initialize
    @proxy = true
  end
end

class NetbootxyzSettings
  attr_accessor :image, :ipxe_timeout

  def initialize
    @image = "docker.io/netbootxyz/netbootxyz"
    @ipxe_timeout = 10
  end
end

class ServiceSettings
  def dnsmasq
    @dnsmasq_config ||= DnsmasqSettings.new
    yield @dnsmasq_config if block_given?
    @dnsmasq_config
  end

  def netbootxyz
    @netbootxyz_config ||= NetbootxyzSettings.new
    yield @netbootxyz_config if block_given?
    @netbootxyz_config
  end
end
```

Add to `Config`:
```ruby
def service
  @service_config ||= ServiceSettings.new
  yield @service_config if block_given?
  @service_config
end
```

### Step 2: Update DnsmasqService to use config DSL

In `lib/pcs/services/dnsmasq_service.rb`, replace:
```ruby
svc = Pcs::Service.find_by_name("dnsmasq")
proxy = svc&.proxy != false
```

With:
```ruby
proxy = Pcs.config.service.dnsmasq.proxy
```

### Step 3: Update NetbootService to use config DSL

In `lib/pcs/services/netboot_service.rb`, replace all `Pcs::Service.definition("netbootxyz")` calls:

In `start`:
```ruby
# Replace:
svc_def = Pcs::Service.definition("netbootxyz")
image = svc_def&.image || "docker.io/netbootxyz/netbootxyz"
# With:
image = Pcs.config.service.netbootxyz.image
```

In `generate_pxe_files`:
```ruby
# Replace:
svc_def = Pcs::Service.definition("netbootxyz")
ipxe_timeout_sec = svc_def&.ipxe_timeout || 10
# With:
ipxe_timeout_sec = Pcs.config.service.netbootxyz.ipxe_timeout
```

In `download_boot_files`: the `Service.definition` fallback for `debian_kernel`/`debian_initrd` will be removed in plan-04. For now, just remove the fallback and use `Platform::Os` exclusively (this is a safe change since the Platform module already has the data):
```ruby
# Replace the entire svc_def conditional block with:
urls = Platform::Os.installer_urls(os, arch)
kernel_url = urls[:kernel_url]
initrd_url = urls[:initrd_url]
```

### Step 4: Simplify ServicesCommand

Rewrite `ServicesCommand` to work without the Service model. The commands become thin wrappers around the two known service classes.

- **List**: Hardcoded list of dnsmasq + netbootxyz with live status check
- **Show**: Live status for the named service, plus relevant config from DSL
- **Set**: Remove entirely — config lives in `pcs.rb`, not mutable at runtime
- **Start/Stop/Restart/Debug**: Keep, but remove Service model lookups and status updates

Remove `Set` from CLI registration. Remove `service set` from `cli.rb`.

### Step 5: Delete Service model and related files

Delete:
- `lib/pcs/models/service.rb`
- `lib/pcs/views/services_view.rb`
- `spec/pcs/models/services_spec.rb`
- `spec/pcs/views/services_view_spec.rb`
- `spec/fixtures/project/data/services.yml`
- `spec/fixtures/project/sites/rok/services.yml`
- `spec/fixtures/project/sites/sg/services.yml`

### Step 6: Remove Service from requires and boot

In `lib/pcs/cli.rb`:
- Remove `require_relative "models/service"`
- Remove the services view require if it's there

In `lib/pcs/boot.rb`:
- Remove `Pcs::Service.reload!` from `reload_models!`

### Step 7: Remove services.yml from project template

Delete `lib/pcs/templates/project/services.yml`.

If `pcs new` copies this file, update the scaffold command to not reference it.

### Step 8: Update pcs.rb template

Update `lib/pcs/templates/project/pcs.rb.erb` to include the service config block:

```ruby
Pcs.configure do |config|
  config.service.dnsmasq do |dns|
    dns.proxy = true
  end

  config.service.netbootxyz do |nb|
    nb.image = "docker.io/netbootxyz/netbootxyz"
    nb.ipxe_timeout = 10
  end

  # ... existing config blocks ...
end
```

Remove `pcs.yml.erb` if still present (it should already be a leftover).

## Test Spec

### New specs: Config DSL

```ruby
# spec/pcs/config_spec.rb (add to existing)
RSpec.describe Pcs::Config do
  describe "service config" do
    it "has dnsmasq defaults" do
      config = Pcs::Config.new
      expect(config.service.dnsmasq.proxy).to eq(true)
    end

    it "has netbootxyz defaults" do
      config = Pcs::Config.new
      expect(config.service.netbootxyz.image).to eq("docker.io/netbootxyz/netbootxyz")
      expect(config.service.netbootxyz.ipxe_timeout).to eq(10)
    end

    it "accepts block configuration" do
      config = Pcs::Config.new
      config.service.dnsmasq do |dns|
        dns.proxy = false
      end
      expect(config.service.dnsmasq.proxy).to eq(false)
    end
  end
end
```

### Verify removals
- No references to `Pcs::Service` as a model (FlatRecord) anywhere
- No `services.yml` in fixtures or templates
- `grep -r "Service\.definition\|Service\.find_by_name\|Service\.load" lib/` returns empty
- `grep -r "data/services\|services\.yml" lib/ spec/` returns empty

### Verify preserved functionality
- `pcs service list` shows dnsmasq and netbootxyz with live status
- `pcs service start dnsmasq` works using config DSL for proxy flag
- `pcs service start netboot` works using config DSL for image
- All specs green

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
grep -r "Service\.definition\|Service\.find_by_name\|Service\.load\b" lib/
grep -r "services\.yml" lib/ spec/
```
