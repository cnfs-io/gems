---
---

# Plan 02 — Image Commands (list, show, delete)

## Context

Read before starting:
- `docs/image-lifecycle/README.md` — tier overview
- `docs/image-lifecycle/plan-01-image-model-and-registry.md` — plan 01 (must be complete)
- `lib/pim/image.rb` — Image value object
- `lib/pim/services/registry.rb` — Registry v2
- `lib/pim/cli.rb` — CLI registry
- `lib/pim/views/` — existing view pattern (RestCli::View)

## Goal

Add `pim image list`, `pim image show`, and `pim image delete` commands that expose the image catalog with status, labels, and lineage.

## Implementation

### Step 1: Create `ImagesView`

**File:** `lib/pim/views/images_view.rb`

The image list should be the most informative view in PIM — this is where the user sees everything at a glance.

```ruby
# frozen_string_literal: true

module Pim
  class ImagesView < RestCli::View
    columns       :id, :status, :label, :parent_id, :size, :age
    detail_fields :id, :profile, :arch, :status, :label, :parent_id,
                  :path, :iso, :provisioned_with, :provisioned_at,
                  :published_at, :build_time, :size, :cache_key

    # Override list to use Image methods for computed fields
    def list(images, **options)
      # Images are already Image objects, not FlatRecord
      # Use the computed methods (human_size, age) for display
      super
    end
  end
end
```

**Note for implementer:** The `Image` value object has `#human_size` and `#age` methods. The view's `columns` reference `:size` and `:age` — verify that RestCli::View calls these methods on the object. If RestCli::View expects hash-style access, you may need to add method aliases or override the column rendering. Check how other views work (e.g., `BuildsView`) and follow the same pattern.

If RestCli::View doesn't work well with non-FlatRecord objects, the list and show commands can format output directly (like `VmCommand::List` does). Use whichever approach is cleaner.

### Step 2: Create `ImageCommand`

**File:** `lib/pim/commands/image_command.rb`

```ruby
# frozen_string_literal: true

module Pim
  class ImageCommand < RestCli::Command
    class List < self
      desc "List all tracked images"

      option :status, type: :string, default: nil,
             desc: "Filter by status (built, verified, provisioned, published)"

      def call(status: nil, **options)
        registry = Pim::Registry.new
        images = registry.all

        images = images.select { |i| i.status == status } if status

        if images.empty?
          puts "No images found."
          return
        end

        # Table format
        puts format("%-4s %-30s %-12s %-14s %-20s %-8s %-8s",
                    "#", "ID", "STATUS", "LABEL", "PARENT", "SIZE", "AGE")
        puts "-" * 100

        images.each_with_index do |img, idx|
          label = img.label || (img.golden? ? "golden" : "—")
          parent = img.parent_id || "—"
          size = img.human_size || "?"
          age = img.age || "?"

          puts format("%-4s %-30s %-12s %-14s %-20s %-8s %-8s",
                      idx + 1, img.id, img.status, label, parent, size, age)
        end
      end
    end

    class Show < self
      desc "Show detailed image information"

      argument :id, required: true, desc: "Image ID"

      def call(id:, **)
        registry = Pim::Registry.new
        image = registry.find(id)

        unless image
          Pim.exit!(1, message: "Image '#{id}' not found. Run 'pim image list' to see available images.")
          return
        end

        puts "Image: #{image.id}"
        puts
        puts "  Profile:      #{image.profile}"
        puts "  Arch:         #{image.arch}"
        puts "  Status:       #{image.status}"
        puts "  Label:        #{image.label || '—'}"
        puts "  Path:         #{image.path}"
        puts "  Exists:       #{image.exists? ? 'yes' : 'NO (missing!)'}"
        puts "  Size:         #{image.human_size || '?'}"
        puts "  ISO:          #{image.iso || '—'}"
        puts "  Built:        #{image.build_time || '—'}"
        puts "  Cache key:    #{image.cache_key || '—'}"

        if image.parent_id
          puts
          puts "  Lineage"
          puts "  Parent:       #{image.parent_id}"
          puts "  Provisioned:  #{image.provisioned_with || '—'}"
          puts "  Prov. time:   #{image.provisioned_at || '—'}"
        end

        if image.published_at
          puts
          puts "  Published:    #{image.published_at}"
        end

        unless image.deployments.empty?
          puts
          puts "  Deployments (#{image.deployments.size}):"
          image.deployments.each do |d|
            puts "    → #{d['target']} (#{d['target_type']}) at #{d['deployed_at']}"
          end
        end
      end
    end

    class Delete < self
      desc "Delete an image from registry and disk"

      argument :id, required: true, desc: "Image ID"

      option :force, type: :boolean, default: false, aliases: ["-f"],
             desc: "Skip confirmation"
      option :keep_file, type: :boolean, default: false,
             desc: "Remove from registry but keep the file on disk"

      def call(id:, force: false, keep_file: false, **)
        registry = Pim::Registry.new
        image = registry.find(id)

        unless image
          Pim.exit!(1, message: "Image '#{id}' not found.")
          return
        end

        # Check for children that depend on this image (CoW overlays)
        children = registry.all.select { |i| i.parent_id == id }
        unless children.empty?
          puts "Warning: #{children.size} image(s) depend on this image as a backing file:"
          children.each { |c| puts "  - #{c.id}" }
          puts
          puts "Deleting this image will make those overlays unusable."
          puts "Delete children first, or publish them (which flattens the overlay)."
          Pim.exit!(1) unless force
        end

        unless force
          print "Delete image '#{id}'? "
          print "(file will be kept) " if keep_file
          print "(y/N) "
          response = $stdin.gets.chomp
          return unless response.downcase == 'y'
        end

        # Remove file from disk
        if !keep_file && image.path && File.exist?(image.path)
          FileUtils.rm_f(image.path)
          # Also clean up EFI vars if present
          efi_vars = image.path.sub(/\.qcow2$/, '-efivars.fd')
          FileUtils.rm_f(efi_vars) if File.exist?(efi_vars)
          puts "Deleted file: #{image.path}"
        end

        registry.delete(id)
        puts "Removed '#{id}' from registry."
      end
    end
  end
end
```

### Step 3: Register in CLI

**File:** `lib/pim/cli.rb`

Add require at top:
```ruby
require_relative "commands/image_command"
```

Add inside `inside_project` block:
```ruby
# Images
register "image list",       ImageCommand::List, aliases: ["ls"]
register "image show",       ImageCommand::Show
register "image delete",     ImageCommand::Delete, aliases: ["rm"]
```

### Step 4: Register view

**File:** `lib/pim/views.rb` (or wherever views are aggregated)

Add: `require_relative "views/images_view"`

Ensure `ImageCommand` can access the view (if it needs one — the commands above use direct puts formatting, which is simpler and avoids the RestCli::View compatibility question with non-FlatRecord objects).

## Test Spec

### Unit tests

**File:** `spec/commands/image_command_spec.rb`

- `ImageCommand::List` is registered at `image list` with alias `ls`
- `ImageCommand::Show` is registered at `image show`
- `ImageCommand::Delete` is registered at `image delete` with alias `rm`
- List with `--status provisioned` filters correctly
- Show with unknown id prints error
- Delete with children warns and exits (unless --force)
- Delete with `--keep-file` removes from registry but not disk

### Manual verification

```bash
# After building an image
pim image list
# Should show: default-arm64, status: built (or verified)

pim image show default-arm64
# Should show full detail

# Delete (will prompt for confirmation)
pim image delete default-arm64

# Filter by status
pim image list --status verified
```

## Verification

- [ ] `pim image list` shows all images with status, label, parent, size, age
- [ ] `pim image list --status provisioned` filters correctly
- [ ] `pim image show <id>` displays full detail including lineage and deployments
- [ ] `pim image show nonexistent` prints friendly error
- [ ] `pim image delete <id>` prompts for confirmation, removes file + registry entry
- [ ] `pim image delete <id> --force` skips confirmation
- [ ] `pim image delete <id> --keep-file` keeps file on disk
- [ ] Deleting an image with children warns about overlay dependency
- [ ] `bundle exec rspec` passes
