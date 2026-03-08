---
---

# Plan 04 — Image Publish (flatten overlay to standalone)

## Context

Read before starting:
- `docs/image-lifecycle/README.md` — tier overview
- `docs/image-lifecycle/plan-01-image-model-and-registry.md` — plan 01 (must be complete)
- `docs/image-lifecycle/plan-02-image-commands.md` — plan 02 (must be complete)
- `lib/pim/image.rb` — Image value object
- `lib/pim/services/registry.rb` — Registry v2
- `lib/pim/services/qemu_disk_image.rb` — disk operations (convert, create_overlay)
- `lib/pim/commands/image_command.rb` — add Publish command

## Goal

Add `pim image publish <id>` which flattens a CoW overlay into a standalone qcow2 that has no backing file dependency. This is the gate between "provisioned" and "ready to deploy." Golden images that are already standalone can also be published (status transition only).

## Background

CoW overlays created by `pim vm run --no-snapshot` depend on their backing file (the golden image). You cannot:
- Move the overlay to another machine without also moving the golden image
- Upload it to Proxmox as a template
- Convert it to an AMI

Publishing resolves this by running `qemu-img convert` which reads the overlay + backing file and writes a standalone qcow2.

## Implementation

### Step 1: Add `Publish` command to `ImageCommand`

**File:** `lib/pim/commands/image_command.rb`

```ruby
class Publish < self
  desc "Publish an image (flatten overlay to standalone qcow2)"

  argument :id, required: true, desc: "Image ID"

  option :compress, type: :boolean, default: false, aliases: ["-c"],
         desc: "Compress the output image"
  option :output, type: :string, default: nil, aliases: ["-o"],
         desc: "Output path (default: replaces overlay in place)"

  def call(id:, compress: false, output: nil, **)
    registry = Pim::Registry.new
    image = registry.find(id)

    unless image
      Pim.exit!(1, message: "Image '#{id}' not found.")
      return
    end

    unless image.exists?
      Pim.exit!(1, message: "Image file missing: #{image.path}")
      return
    end

    case image.status
    when 'published'
      puts "Image '#{id}' is already published."
      return
    when 'built', 'verified'
      # Golden image — no overlay to flatten, just transition status
      if golden_standalone?(image.path)
        registry.update_status(id, 'published')
        puts "Published '#{id}' (already standalone, status updated)."
        return
      end
    end

    # Determine output path
    if output
      dest = File.expand_path(output)
    else
      # Replace in place: write to .tmp, then swap
      dest = "#{image.path}.publish-tmp"
    end

    puts "Publishing '#{id}'..."
    puts "  Source:     #{image.path}"
    puts "  Compress:   #{compress}"

    # Flatten via qemu-img convert
    disk = Pim::QemuDiskImage.new(image.path)
    begin
      disk.convert(dest, format: 'qcow2', compress: compress)
    rescue Pim::QemuDiskImage::Error => e
      # Clean up temp file on failure
      FileUtils.rm_f(dest) if dest.end_with?('.publish-tmp')
      Pim.exit!(1, message: "Publish failed: #{e.message}")
      return
    end

    # If replacing in place, swap files
    unless output
      original = image.path
      FileUtils.mv(dest, original)
      dest = original
    end

    # Update registry
    final_size = File.size(dest)
    entry = registry.find!(id)  # re-read
    # Update path if output was specified
    if output
      # Update the raw entry's path
      registry.instance_variable_get(:@data)['images'][id]['path'] = dest
      registry.instance_variable_get(:@data)['images'][id]['filename'] = File.basename(dest)
    end
    registry.update_status(id, 'published')

    original_size = image.size || 0
    puts "  Output:     #{dest}"
    puts "  Size:       #{format_size(final_size)} (was #{format_size(original_size)})"
    puts "Published '#{id}' successfully."
  end

  private

  def golden_standalone?(path)
    # Check if image has a backing file
    disk = Pim::QemuDiskImage.new(path)
    info = disk.info
    !info.key?('backing-filename')
  rescue StandardError
    true  # Assume standalone if we can't check
  end

  def format_size(bytes)
    return "?" unless bytes && bytes > 0
    if bytes > 1_073_741_824
      format("%.1fG", bytes.to_f / 1_073_741_824)
    elsif bytes > 1_048_576
      format("%.1fM", bytes.to_f / 1_048_576)
    else
      format("%.1fK", bytes.to_f / 1024)
    end
  end
end
```

### Step 2: Register in CLI

**File:** `lib/pim/cli.rb`

Add to the Images section:
```ruby
register "image publish",    ImageCommand::Publish
```

### Step 3: Add `auto_publish` support to deploy (forward-looking)

When `config.images.auto_publish` is true, the deploy command (plan 05/06) should automatically publish before deploying if the image isn't already published. This is just a note for plan 05 — no implementation needed here.

Document the check pattern that deploy should use:

```ruby
# In deploy command:
if image.overlay? && !image.published?
  if Pim.config.images.auto_publish
    puts "Auto-publishing overlay before deploy..."
    # call publish logic
  else
    Pim.exit!(1, message: "Image '#{id}' is an overlay and must be published first.\n" \
                          "Run: pim image publish #{id}\n" \
                          "Or set config.images.auto_publish = true in pim.rb")
  end
end
```

## Test Spec

### Unit tests

**File:** `spec/commands/image_command_spec.rb` (extend)

- `Publish` registered at `image publish`
- Publishing a standalone golden image transitions status without flattening
- Publishing an already-published image is a no-op with message
- Publishing a missing image errors
- `--compress` flag is passed through to qemu-img convert
- `--output` writes to custom path instead of in-place

**File:** `spec/services/qemu_disk_image_spec.rb` (extend)

- `#info` returns hash with or without `backing-filename`
- `#convert` with `compress: true` passes `-c` flag

### Manual verification

```bash
# Provision an image first (creates overlay)
pim vm run default-arm64 --run /tmp/test.sh --label test-pub

# Check it's an overlay
qemu-img info ~/.local/share/pim/vms/default-arm64-test-pub.qcow2
# Should show "backing file: ..."

# Publish
pim image publish default-arm64-test-pub
# Should flatten, report sizes

# Verify standalone
qemu-img info ~/.local/share/pim/vms/default-arm64-test-pub.qcow2
# Should NOT show "backing file"

pim image show default-arm64-test-pub
# Status should be "published"

# Publish a golden image (status transition only)
pim image publish default-arm64
# Should say "already standalone, status updated"

# Publish with compression
pim image publish default-arm64-test-pub --compress
# Should produce smaller file
```

## Verification

- [ ] `pim image publish <overlay>` flattens to standalone qcow2
- [ ] Published image has no backing file dependency (`qemu-img info`)
- [ ] `pim image publish <golden>` transitions status without flattening
- [ ] `pim image publish <already-published>` is a no-op
- [ ] `--compress` reduces output size
- [ ] `--output` writes to custom path
- [ ] Registry updated with new status, published_at, size
- [ ] Failed publish cleans up temp file
- [ ] `bundle exec rspec` passes
