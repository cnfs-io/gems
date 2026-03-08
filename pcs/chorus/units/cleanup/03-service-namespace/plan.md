---
---

# Plan 03 — Service Namespace

## Context

Read before starting:
- `lib/pcs/services/dnsmasq_service.rb` — rename to `Pcs::Service::Dnsmasq`
- `lib/pcs/services/netboot_service.rb` — rename to `Pcs::Service::Netbootxyz`
- `lib/pcs/services/control_plane_service.rb` — rename to `Pcs::Service::ControlPlane`
- `lib/pcs/commands/services_command.rb` — update class references
- `lib/pcs/cli.rb` — update requires
- `lib/pcs/config.rb` — `ServiceSettings` already exists from plan-02

## Implementation

### Step 1: Create service/ directory and module

Create `lib/pcs/service.rb`:
```ruby
# frozen_string_literal: true

module Pcs
  module Service
  end
end
```

### Step 2: Move and rename DnsmasqService

Move `lib/pcs/services/dnsmasq_service.rb` → `lib/pcs/service/dnsmasq.rb`

Rename class:
```ruby
# From:
module Pcs
  module Services
    class DnsmasqService
# To:
module Pcs
  module Service
    class Dnsmasq
```

All method signatures stay the same. Only the class name and namespace change.

### Step 3: Move and rename NetbootService

Move `lib/pcs/services/netboot_service.rb` → `lib/pcs/service/netbootxyz.rb`

Rename class:
```ruby
# From:
module Pcs
  module Services
    class NetbootService
# To:
module Pcs
  module Service
    class Netbootxyz
```

### Step 4: Move and rename ControlPlaneService

Move `lib/pcs/services/control_plane_service.rb` → `lib/pcs/service/control_plane.rb`

Rename class:
```ruby
# From:
module Pcs
  module Services
    class ControlPlaneService
# To:
module Pcs
  module Service
    class ControlPlane
```

### Step 5: Delete services/ directory

After moving all files, remove the now-empty `lib/pcs/services/` directory.

### Step 6: Update CLI requires

In `lib/pcs/cli.rb`, replace:
```ruby
require_relative "services/control_plane_service"
require_relative "services/dnsmasq_service"
require_relative "services/netboot_service"
```

With:
```ruby
require_relative "service"
require_relative "service/control_plane"
require_relative "service/dnsmasq"
require_relative "service/netbootxyz"
```

### Step 7: Update ServicesCommand references

In `lib/pcs/commands/services_command.rb`, update all class references:

```ruby
# From:
Services::DnsmasqService
Services::NetbootService
# To:
Service::Dnsmasq
Service::Netbootxyz
```

Update `SERVICE_CHECKS`:
```ruby
SERVICE_CHECKS = {
  dnsmasq: Service::Dnsmasq,
  netboot: Service::Netbootxyz
}.freeze
```

Update `SERVICE_MAP` in `Debug`:
```ruby
SERVICE_MAP = {
  "dnsmasq" => Service::Dnsmasq,
  "netboot" => Service::Netbootxyz
}.freeze
```

Update `Start`, `Stop`, `Restart` case statements to use new class names.

### Step 8: Update CpCommand references

In `lib/pcs/commands/cp_command.rb` (if it references ControlPlaneService):
```ruby
# From:
Services::ControlPlaneService
# To:
Service::ControlPlane
```

### Step 9: Update any specs

Rename spec files to match new structure:
- `spec/pcs/services/` → `spec/pcs/service/`

Update class references in all spec files.

## Test Spec

### Verify namespace
- `Pcs::Service::Dnsmasq` responds to `.start`, `.stop`, `.status`, `.debug`
- `Pcs::Service::Netbootxyz` responds to `.start`, `.stop`, `.status`, `.debug`
- `Pcs::Service::ControlPlane` responds to `#apply_static_ip`, `#restart_networking`
- No references to `Pcs::Services::` (old plural namespace) anywhere

### Verify preserved functionality
- All existing service specs pass under new namespace
- `pcs service start dnsmasq` works
- `pcs service debug netboot` works

## Verification

```bash
cd ~/spaces/rws/repos/rws-pcs/claude-test
bundle exec rspec
grep -r "Pcs::Services\b" lib/ spec/     # should return empty
grep -r "Services::" lib/ spec/           # should return empty
ls lib/pcs/services/                       # should not exist
```
