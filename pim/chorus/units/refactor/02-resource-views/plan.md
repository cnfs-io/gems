---
---

# Plan 02 — Resource Views

## Objective

Create view classes for Iso, Build, and Target models. These views define column layouts for list and detail rendering, eliminating the hand-rolled `puts` calls in the current get commands.

## Context

Read before starting:
- `lib/pim/views/profiles_view.rb` — existing view (updated in plan 01)
- `lib/pim/views.rb` — view require file
- `lib/pim/models/iso.rb` — Iso model attributes
- `lib/pim/models/build.rb` — Build model attributes
- `lib/pim/models/target.rb` — Target model attributes
- `lib/pim/commands/iso/get.rb` — current hand-rolled rendering (to understand what's displayed today)
- `lib/pim/commands/build/get.rb` — current hand-rolled rendering
- `lib/pim/commands/target/get.rb` — current hand-rolled rendering

## Implementation Spec

### `lib/pim/views/isos_view.rb`

```ruby
# frozen_string_literal: true

module Pim
  class IsosView < RestCli::View
    columns       :id, :architecture, :name
    detail_fields :id, :name, :architecture, :url, :checksum, :checksum_url, :filename
  end
end
```

Column selection rationale: the current `iso get` list shows `id`, `architecture`, `name` — matching exactly. Detail fields include all meaningful attributes.

### `lib/pim/views/builds_view.rb`

```ruby
# frozen_string_literal: true

module Pim
  class BuildsView < RestCli::View
    columns       :id, :profile, :distro, :arch
    detail_fields :id, :profile, :iso, :distro, :automation, :build_method,
                  :arch, :target, :disk_size, :memory, :cpus
  end
end
```

Column selection rationale: the current `build get` list shows `id`, `profile`, `distro`, `arch` — matching exactly.

### `lib/pim/views/targets_view.rb`

```ruby
# frozen_string_literal: true

module Pim
  class TargetsView < RestCli::View
    columns       :id, :type, :name
    detail_fields :id, :type, :name, :parent_id
  end
end
```

Column selection rationale: the current `target get` list shows `id`, `type`, `name` — matching exactly. Detail fields are kept minimal since targets use STI and subclasses have different attributes. The resolved_attributes pattern may need custom rendering in the future, but this covers the base case.

### `lib/pim/views.rb` — update requires

```ruby
require "rest_cli"

require_relative "views/profiles_view"
require_relative "views/isos_view"
require_relative "views/builds_view"
require_relative "views/targets_view"
```

### Design notes

- View column selections match what the current hand-rolled commands display. No new columns are added — this is a pure refactor, not a feature change.
- Target detail rendering is intentionally simple. The current `target get <id>` uses `target.to_h` which calls `resolved_attributes` (walks parent chain). The view's `show` method will use the declared `detail_fields` which calls attribute accessors directly — this may show unresolved (nil) values for inherited attributes. If this is a problem, the command's `show` action can pass a decorated record or override the view. Flag this during testing.
- Build and Iso models are read-only, so no Create/Update/Delete views are needed (those commands don't exist).

## Test Spec

### `spec/pim/views/isos_view_spec.rb`

```ruby
# frozen_string_literal: true

RSpec.describe Pim::IsosView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:id, :architecture, :name])
  end

  it "has detail fields" do
    expect(described_class.detail_fields).to include(:id, :name, :url)
  end
end
```

### `spec/pim/views/builds_view_spec.rb`

```ruby
# frozen_string_literal: true

RSpec.describe Pim::BuildsView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:id, :profile, :distro, :arch])
  end
end
```

### `spec/pim/views/targets_view_spec.rb`

```ruby
# frozen_string_literal: true

RSpec.describe Pim::TargetsView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:id, :type, :name])
  end
end
```

## Verification

```bash
# New views load
bundle exec ruby -e "require 'pim'; puts Pim::IsosView.columns.inspect"
bundle exec ruby -e "require 'pim'; puts Pim::BuildsView.columns.inspect"
bundle exec ruby -e "require 'pim'; puts Pim::TargetsView.columns.inspect"

# Specs
bundle exec rspec spec/pim/views/

# Full suite green
bundle exec rspec
```
