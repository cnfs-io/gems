---
---

# Plan 08: Target Model with STI

## Context

Read these files before starting:

- `lib/pim/models/build.rb` — Build model with `target` field (string reference, added in plan 07)
- `lib/pim/models.rb` — FlatRecord configuration
- FlatRecord `lib/flat_record/store.rb` — how records are loaded and instantiated
- FlatRecord `lib/flat_record/base.rb` — class-level config methods

**Prerequisites:**
- Plan 07 complete (Build model with `target` field)
- FlatRecord extension `plan-02-sti` complete (see below)

**Note:** This plan has a FlatRecord dependency. FlatRecord needs STI support before PIM can use typed Target subclasses. The FlatRecord extension plan is included below and should be implemented first.

## Objective

1. Create a `Pim::Target` base model with STI subclasses per target type
2. Each subclass has type-specific attributes and deploy logic
3. Build records reference targets by ID
4. `target get/set` commands follow the same API pattern

## FlatRecord STI Extension (prerequisite)

FlatRecord needs a `type` field that maps to subclasses. When loading records, if a `type` attribute is present and a matching subclass exists, FlatRecord instantiates the subclass instead of the base class.

### How it works

```ruby
class Target < FlatRecord::Base
  source "targets"
  sti_column :type   # declares this model uses STI
end

class ProxmoxTarget < Target
  sti_type "proxmox"
  
  attribute :host, :string
  attribute :node, :string
  attribute :storage, :string
  attribute :api_token_id, :string
end

class AwsTarget < Target
  sti_type "aws"
  
  attribute :region, :string
  attribute :instance_type, :string
  attribute :ami_name_prefix, :string
end
```

When FlatRecord loads `targets.yml`, it reads the `type` field on each record and instantiates the matching subclass. `Target.all` returns a mixed array of `ProxmoxTarget`, `AwsTarget`, `LocalTarget`, etc. `Target.find("proxmox-sg")` returns a `ProxmoxTarget` instance.

The subclass registers itself with the base class via `sti_type`. The base class maintains a registry:

```ruby
class Base
  def self.sti_column(col = nil)
    if col
      @sti_column = col.to_s
    else
      @sti_column
    end
  end

  def self.sti_type(type_name = nil)
    if type_name
      @sti_type = type_name.to_s
      # Register with parent
      superclass.sti_types[type_name.to_s] = self if superclass.respond_to?(:sti_types)
    else
      @sti_type
    end
  end

  def self.sti_types
    @sti_types ||= {}
  end
end
```

In Store, when loading a record:

```ruby
def instantiate_record(hash)
  klass = model_class
  if model_class.sti_column
    type_val = hash[model_class.sti_column]
    subclass = model_class.sti_types[type_val]
    klass = subclass if subclass
  end
  record = klass.new(hash)
  record.clear_changes_information
  record
end
```

### FlatRecord STI plan

This should be written as `docs/extensions/plan-02-sti.md` in the FlatRecord gem. Key requirements:

- `sti_column :type` on base class
- `sti_type "name"` on subclasses auto-registers
- Store instantiates correct subclass when loading
- `Base.all` returns mixed subclass instances
- `Base.find(id)` returns the correct subclass
- Subclasses can define additional attributes
- Subclasses inherit base class attributes
- `SubClass.all` returns only records of that type (scope by type)
- Works with both collection and individual file layouts
- Works with multi-path loading
- Respects read_only settings
- Does not break existing models that don't use STI

## PIM Target implementation

### Target base model

Create `lib/pim/models/target.rb`:

```ruby
# frozen_string_literal: true

module Pim
  class Target < FlatRecord::Base
    source "targets"
    read_only true
    sti_column :type

    attribute :type, :string
    attribute :parent_id, :string
    attribute :name, :string           # human-friendly name

    def parent
      return nil unless parent_id
      self.class.find(parent_id)
    end

    # Same parent chain resolution as Profile
    def parent_chain
      chain = [self]
      current = self
      seen = Set.new([id])

      while current.parent_id
        raise "Circular parent_id reference: #{current.parent_id}" if seen.include?(current.parent_id)
        seen << current.parent_id
        current = self.class.find(current.parent_id)
        chain.unshift(current)
      end

      chain
    end

    def resolved_attributes
      chain = parent_chain
      result = {}
      chain.each do |target|
        result = result.deep_merge(target.attributes.compact.except("id", "parent_id"))
      end
      result.merge("id" => id)
    end

    def to_h
      resolved_attributes
    end

    def raw_to_h
      attributes.compact
    end

    # Subclasses implement this
    def deploy(image_path)
      raise NotImplementedError, "#{self.class.name} must implement #deploy"
    end
  end
end
```

### Target subclasses

Create `lib/pim/models/targets/local.rb`:

```ruby
# frozen_string_literal: true

module Pim
  class LocalTarget < Target
    sti_type "local"

    # Local target — image stays on disk. No deploy action needed.
    def deploy(image_path)
      puts "Image available at: #{image_path}"
      true
    end
  end
end
```

Create `lib/pim/models/targets/proxmox.rb`:

```ruby
# frozen_string_literal: true

module Pim
  class ProxmoxTarget < Target
    sti_type "proxmox"

    attribute :host, :string
    attribute :node, :string
    attribute :storage, :string
    attribute :api_token_id, :string
    attribute :api_token_secret, :string  # consider: should this be in config, not YAML?
    attribute :vm_id_start, :integer      # starting VM ID for auto-assignment
    attribute :bridge, :string            # network bridge (e.g., vmbr0)

    def deploy(image_path)
      # TODO: implement Proxmox upload via API
      # 1. Upload qcow2 to storage
      # 2. Create VM with specified resources
      # 3. Attach disk
      raise NotImplementedError, "Proxmox deploy not yet implemented"
    end
  end
end
```

Create `lib/pim/models/targets/aws.rb`:

```ruby
# frozen_string_literal: true

module Pim
  class AwsTarget < Target
    sti_type "aws"

    attribute :region, :string
    attribute :instance_type, :string
    attribute :ami_name_prefix, :string
    attribute :subnet_id, :string
    attribute :security_group_ids, :string
    attribute :iam_role, :string

    def deploy(image_path)
      # TODO: implement AWS AMI creation
      # 1. Upload to S3
      # 2. Import as snapshot
      # 3. Register as AMI
      raise NotImplementedError, "AWS deploy not yet implemented"
    end
  end
end
```

Create `lib/pim/models/targets/iso_target.rb`:

```ruby
# frozen_string_literal: true

module Pim
  class IsoTarget < Target
    sti_type "iso"

    attribute :output_dir, :string  # where to store repacked ISOs

    def deploy(image_path)
      # For iso-repack build method, the "deploy" is just noting where the ISO is
      puts "Repacked ISO available at: #{image_path}"
      true
    end
  end
end
```

### Register models

In `lib/pim/models.rb`:

```ruby
require_relative "models/target"
require_relative "models/targets/local"
require_relative "models/targets/proxmox"
require_relative "models/targets/aws"
require_relative "models/targets/iso_target"
```

Add `Pim::Target.reload!` to `configure_flat_record!`.

### Scaffold template

Create `lib/pim/templates/project/targets.yml`:

```yaml
# PIM Deploy Targets
# Each target defines where built images are deployed.
# The 'type' field determines the target class and available attributes.
#
# Types: local, proxmox, aws, iso
#
# Use parent_id to inherit from a base target:
#   - id: proxmox
#     type: proxmox
#     host: 192.168.1.100
#   - id: proxmox-dev
#     type: proxmox
#     parent_id: proxmox
#     node: pve-dev
---
- id: local
  type: local
```

### Target commands

Create `lib/pim/commands/target/get.rb`:

Same get pattern as profile and iso:

```
pim target get                        # list all targets (with type)
pim target get proxmox-sg             # show all fields (resolved)
pim target get proxmox-sg host        # just the host value
```

Register:

```ruby
register "target",      Commands::Target
register "target get",  Commands::Target::Get
register "target ls",   Commands::Target::Get
```

### Update Build to resolve Target

In `lib/pim/models/build.rb`, add:

```ruby
def resolved_target
  return nil unless target
  Pim::Target.find(target)
end
```

## Test spec

### `spec/pim/models/target_spec.rb`

- `Target.all` returns all targets
- `Target.find("local")` returns a `LocalTarget` instance
- `Target.find("proxmox-sg")` returns a `ProxmoxTarget` instance
- STI: type field determines subclass
- ProxmoxTarget has `host`, `node`, `storage` attributes
- AwsTarget has `region`, `instance_type` attributes
- `parent_id` chain resolution works (same as Profile)
- `resolved_attributes` merges parent target attributes
- `to_h` returns resolved attributes
- Read-only (save raises)
- `ProxmoxTarget.all` returns only proxmox targets (scoped by type)

### `spec/pim/models/build_spec.rb` (additions)

- `build.resolved_target` returns the Target subclass instance
- `build.resolved_target` returns nil when no target set

### `spec/pim/commands/target/get_spec.rb`

- No args: lists all targets with type
- With ID: shows resolved fields
- With ID and field: shows value

## Verification

```bash
# All specs pass
bundle exec rspec

# Target STI works in console
pim c
pim> Target.all.map { |t| [t.id, t.class.name] }
#=> [["local", "Pim::LocalTarget"], ["proxmox-sg", "Pim::ProxmoxTarget"]]

pim> t = Target.find("proxmox-sg")
pim> t.class       #=> Pim::ProxmoxTarget
pim> t.host         #=> "192.168.1.100"
pim> t.type         #=> "proxmox"

# Parent chain
pim> Target.find("proxmox-sg").parent.id  #=> "proxmox"

# Scoped query
pim> ProxmoxTarget.all.map(&:id)  #=> ["proxmox", "proxmox-sg", "proxmox-ny"]

# Build resolves target
pim> Build.find("dev-debian").resolved_target.class
#=> Pim::ProxmoxTarget

# Target get
pim target get
pim target get proxmox-sg
pim target get proxmox-sg host
```
