---
---

# Plan 01 — Add RestCli and Views

## Objective

Add rest_cli as a dependency and create view classes for the three FlatRecord-backed resources: Device, Service, and Site. After this plan, views are available for use but commands are not yet refactored.

## Context

Read before starting:
- `pcs.gemspec` — add rest_cli dependency
- `lib/pcs/models/device.rb` — Device attributes and FIELDS constant
- `lib/pcs/models/service.rb` — Service attributes
- `lib/pcs/models/site.rb` — Site attributes
- `lib/pcs/commands/device/get.rb` — current hand-rolled table rendering (columns to match)
- `lib/pcs/commands/service/get.rb` — current hand-rolled table rendering
- `lib/pcs/commands/site/get.rb` — current hand-rolled table rendering

## Implementation Spec

### Add rest_cli dependency

In `pcs.gemspec`:

```ruby
spec.add_dependency "rest_cli"
```

### Create views directory and require file

```ruby
# lib/pcs/views.rb
require "rest_cli"

require_relative "views/devices_view"
require_relative "views/services_view"
require_relative "views/sites_view"
```

Add `require_relative "views"` to the appropriate place in `lib/pcs/cli.rb` (after models, before commands).

### `lib/pcs/views/devices_view.rb`

Column selection matches current `device get` table output: ID, MAC, IP, Hostname, Type, Status.

```ruby
# frozen_string_literal: true

module Pcs
  class DevicesView < RestCli::View
    columns       :id, :mac, :discovered_ip, :hostname, :type, :status
    detail_fields :id, :mac, :discovered_ip, :compute_ip, :storage_ip,
                  :hostname, :connect_as, :type, :role, :arch, :status,
                  :preseed_interface, :discovered_at, :last_seen_at
  end
end
```

### `lib/pcs/views/services_view.rb`

Column selection matches current `service get` table output: Service (name), Status.

```ruby
# frozen_string_literal: true

module Pcs
  class ServicesView < RestCli::View
    columns       :name, :status
    detail_fields :name, :status, :auth_key, :proxy
  end
end
```

Note: The current `service get` shows live status (queried from systemctl), not the stored status field. The view will render what's on the model. The command's Show action may need to decorate the model with live status before passing to the view, or the List action can continue to handle this specially. This is addressed in plan 02.

### `lib/pcs/views/sites_view.rb`

Column selection matches current `site get` table output: marker, Site (name), Domain, Compute subnet, Storage subnet.

The Site model has a non-standard structure — networks are loaded from a nested YAML, not flat attributes. The view needs columns that map to methods on the model.

```ruby
# frozen_string_literal: true

module Pcs
  class SitesView < RestCli::View
    columns       :name, :domain
    detail_fields :name, :domain, :timezone, :ssh_key
  end
end
```

Note: The current site list also shows compute/storage subnets and an active marker. These come from `site.network(:compute)[:subnet]` which isn't a flat attribute. The List action in plan 02 may need custom rendering for the table (passing decorated data or adding computed columns). Keep the view simple for now — plan 02 handles the integration.

### Design notes

- Views are at `Pcs::DevicesView`, not `Pcs::Models::DevicesView`. This matches the rest_cli convention where views are top-level in the app namespace.
- The view class names follow the pattern: plural resource + "View" -> `DevicesView`, `ServicesView`, `SitesView`.
- RestCli::Command's view lookup convention derives `DevicesView` from `DevicesCommand`. Since both are under `Pcs::`, this works: `Pcs::DevicesCommand` -> `Pcs::DevicesView`.

## Test Spec

### `spec/pcs/views/devices_view_spec.rb`

```ruby
# frozen_string_literal: true

RSpec.describe Pcs::DevicesView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:id, :mac, :discovered_ip, :hostname, :type, :status])
  end

  it "has detail fields" do
    expect(described_class.detail_fields).to include(:id, :mac, :hostname, :role, :arch)
  end
end
```

### `spec/pcs/views/services_view_spec.rb`

```ruby
# frozen_string_literal: true

RSpec.describe Pcs::ServicesView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:name, :status])
  end
end
```

### `spec/pcs/views/sites_view_spec.rb`

```ruby
# frozen_string_literal: true

RSpec.describe Pcs::SitesView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:name, :domain])
  end
end
```

## Verification

```bash
# Views load correctly
bundle exec ruby -e "require 'pcs'; puts Pcs::DevicesView.columns.inspect"
bundle exec ruby -e "require 'pcs'; puts Pcs::ServicesView.columns.inspect"
bundle exec ruby -e "require 'pcs'; puts Pcs::SitesView.columns.inspect"

# Specs pass
bundle exec rspec spec/pcs/views/

# Full suite green (nothing broken)
bundle exec rspec
```
