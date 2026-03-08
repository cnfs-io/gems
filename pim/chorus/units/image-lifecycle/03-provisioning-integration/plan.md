---
---

# Plan 03 — Provisioning Integration (--label and registry tracking)

## Context

Read before starting:
- `docs/image-lifecycle/README.md` — tier overview
- `docs/image-lifecycle/plan-01-image-model-and-registry.md` — plan 01 (must be complete)
- `docs/image-lifecycle/plan-02-image-commands.md` — plan 02 (must be complete)
- `lib/pim/commands/vm_command.rb` — `VmCommand::Run` (add --label flag)
- `lib/pim/services/vm_runner.rb` — `VmRunner` (register provisioned image after script completes)
- `lib/pim/config.rb` — `ImageSettings` (require_label setting from plan 01)

## Goal

Wire the `--label` flag into `pim vm run --run` so that successfully provisioned images are registered in the image registry with full lineage metadata. Enforce or auto-generate labels based on the project's `config.images.require_label` setting.

## Implementation

### Step 1: Add `--label` flag to `VmCommand::Run`

**File:** `lib/pim/commands/vm_command.rb`

Add option:

```ruby
option :label, type: :string, default: nil,
       desc: "Label for the provisioned image (required when images.require_label is true)"
```

### Step 2: Add label validation logic

In `VmCommand::Run#call`, after parsing `script_path`:

```ruby
if script_path
  label = resolve_label(label, script_path)
end
```

Add private method:

```ruby
def resolve_label(label, script_path)
  if label
    # Validate label format: lowercase, alphanumeric, hyphens
    unless label.match?(/\A[a-z0-9][a-z0-9\-]*\z/)
      Pim.exit!(1, message: "Invalid label '#{label}'. Use lowercase alphanumeric and hyphens.")
      return
    end
    label
  elsif Pim.config.images.require_label
    Pim.exit!(1, message: "--run requires --label to track the provisioned image.\n" \
                          "Set config.images.require_label = false in pim.rb to auto-generate labels.")
    nil
  else
    # Auto-generate from script filename
    File.basename(script_path, '.*')
        .gsub(/[^a-z0-9\-]/, '-')
        .gsub(/-+/, '-')
        .gsub(/\A-|-\z/, '')
  end
end
```

### Step 3: Pass label through to VmRunner

Update the provisioning path in `VmCommand::Run#call`:

```ruby
if script_path
  label = resolve_label(label, script_path)
  return unless label  # resolve_label may exit

  runner.run(
    snapshot: snapshot, clone: clone, console: false,
    memory: memory, cpus: cpus, bridged: bridged, bridge: bridge
  )

  result = runner.provision(script_path, verbose: true)

  if result[:exit_code] == 0
    puts "\nProvisioning complete (exit code 0)"

    # Register provisioned image
    image = runner.register_image(label: label, script: script_path)
    puts "Image registered: #{image.id}"
  else
    puts "\nProvisioning failed (exit code #{result[:exit_code]})"
    puts "Image NOT registered (provisioning must succeed to track)"
  end

  if shutdown_after
    puts "Shutting down VM..."
    runner.stop
  else
    puts "VM is still running."
    puts "Stop with: pim vm stop #{runner.instance_name}"
  end
end
```

### Step 4: Add `register_image` to VmRunner

**File:** `lib/pim/services/vm_runner.rb`

Add method to register the provisioned overlay/clone in the image registry:

```ruby
# Register the current image as a provisioned variant in the image registry.
# Call after successful provisioning.
def register_image(label:, script:)
  raise Error, "Cannot register: no image path" unless @image_path
  raise Error, "Cannot register: image is a snapshot (ephemeral)" if @snapshot

  parent_id = "#{@profile.id}-#{@arch}"

  registry = Pim::Registry.new
  registry.register_provisioned(
    parent_id: parent_id,
    label: label,
    path: @image_path,
    script: script
  )
end
```

Also store `@snapshot` in the `run` method so `register_image` can check it:

```ruby
def run(snapshot: true, clone: false, ...)
  @snapshot = snapshot
  # ... rest of existing code ...
end
```

### Step 5: Update image naming in `prepare_image`

When a label is known at run time, the overlay/clone file should use the label in its name instead of a timestamp. Update `VmRunner#prepare_image`:

Currently:
```ruby
dest = File.join(vm_dir, "#{@name}-#{timestamp}.qcow2")
```

Change to accept an optional label parameter, or — simpler — have `register_image` rename the file after provisioning:

Actually, the simplest approach: let `prepare_image` keep the timestamp naming (it needs a unique name at boot time before we know if provisioning succeeds). Then in `register_image`, rename/move the file to the labeled name:

```ruby
def register_image(label:, script:)
  raise Error, "Cannot register: no image path" unless @image_path
  raise Error, "Cannot register: image is a snapshot (ephemeral)" if @snapshot

  parent_id = "#{@profile.id}-#{@arch}"
  final_name = "#{parent_id}-#{label}.qcow2"
  final_path = File.join(File.dirname(@image_path), final_name)

  # Rename file to labeled name (if not already there)
  if @image_path != final_path
    FileUtils.mv(@image_path, final_path)
    # Update EFI vars path too
    old_efi = "#{@image_path}-efivars.fd"
    new_efi = "#{final_path}-efivars.fd"
    FileUtils.mv(old_efi, new_efi) if File.exist?(old_efi)
    @image_path = final_path
    # Update VM registry if running
    @registry&.update(@instance_name, image_path: final_path)
  end

  registry = Pim::Registry.new
  registry.register_provisioned(
    parent_id: parent_id,
    label: label,
    path: final_path,
    script: script
  )
end
```

### Step 6: Handle re-provisioning (same label)

If a user runs `--run --label k8s-node` twice, the second run should replace the existing provisioned image. The `Registry#register_provisioned` method writes to `raw_images[id]` which naturally overwrites. But we should warn:

In `VmCommand::Run#call`, before running the VM:

```ruby
if label
  registry = Pim::Registry.new
  existing = registry.find("#{build.id}-#{label}")
  if existing
    puts "Note: Image '#{existing.id}' already exists and will be replaced."
  end
end
```

## Test Spec

### Unit tests

**File:** `spec/commands/vm_command_spec.rb` (extend)

- `--run` without `--label` errors when `require_label` is true
- `--run` without `--label` auto-generates label when `require_label` is false
- `--label` validates format (rejects uppercase, spaces, special chars)
- Auto-generated label from `setup-k8s-node.sh` → `setup-k8s-node`

**File:** `spec/services/vm_runner_spec.rb` (extend)

- `#register_image` raises for snapshot mode
- `#register_image` renames overlay file to labeled name
- `#register_image` calls `registry.register_provisioned` with correct params

**File:** `spec/services/registry_spec.rb` (extend)

- `#register_provisioned` creates image with parent lineage
- `#register_provisioned` with existing label overwrites entry
- Provisioned image appears in `#all` with status 'provisioned'

### Manual verification

```bash
# With require_label = true (default)
pim vm run default-arm64 --run /tmp/test.sh
# Should error: "--run requires --label..."

pim vm run default-arm64 --run /tmp/test.sh --label k8s-node
# Should: boot, provision, register image, print "Image registered: default-arm64-k8s-node"

pim image list
# Should show both: default-arm64 (golden) and default-arm64-k8s-node (provisioned)

pim image show default-arm64-k8s-node
# Should show lineage, provisioned_with, etc.

# With require_label = false
# Edit pim.rb: config.images { |i| i.require_label = false }
pim vm run default-arm64 --run /tmp/setup-postgres.sh
# Should auto-generate label "setup-postgres"
```

## Verification

- [ ] `--run` without `--label` errors when `require_label` is true
- [ ] `--run` without `--label` auto-generates label when `require_label` is false
- [ ] `--run --label k8s-node` registers image as `default-arm64-k8s-node`
- [ ] Failed provisioning does NOT register the image
- [ ] `pim image list` shows provisioned image with parent lineage
- [ ] `pim image show` shows provisioning metadata (script, time)
- [ ] Overlay file is renamed to include label
- [ ] Re-provisioning with same label replaces existing image
- [ ] Invalid labels are rejected with clear error message
- [ ] `bundle exec rspec` passes
