---
---

# Plan 01 — Image Model and Registry Evolution

## Context

Read before starting:
- `docs/image-lifecycle/README.md` — tier overview
- `lib/pim/services/registry.rb` — current Registry (v1 schema, keyed by profile-arch)
- `lib/pim/config.rb` — Config DSL (add images block)
- `lib/pim/build/manager.rb` — where golden images are registered after build
- `lib/pim.rb` — main module (XDG paths, constants)

## Goal

Evolve the Registry from a flat hash to a v2 schema that supports image lineage, status tracking, provisioning metadata, and labels. Add an `Image` value object for clean access. Add `images` config block to the DSL. Maintain backward compatibility with v1 registry files (auto-migrate on load).

## Implementation

### Step 1: Add `ImageSettings` config and wire into DSL

**File:** `lib/pim/config.rb`

Add a new settings class and accessor:

```ruby
class ImageSettings
  attr_accessor :require_label, :auto_publish

  def initialize
    @require_label = true      # --run requires --label by default
    @auto_publish = false      # require explicit publish before deploy
  end
end
```

Add to `Config`:

```ruby
class Config
  attr_accessor :iso_dir, :image_dir,
                :serve_port, :serve_profile

  def initialize
    # ... existing ...
    @images = ImageSettings.new
  end

  def images
    yield @images if block_given?
    @images
  end

  # ... existing ventoy, flat_record ...
end
```

Usage in `pim.rb`:

```ruby
Pim.configure do |config|
  config.images do |img|
    img.require_label = false
  end
end
```

### Step 2: Create `Pim::Image` value object

**File:** `lib/pim/image.rb`

This is NOT a FlatRecord model — images are machine-local state in the registry YAML, not project data. It's a simple Ruby object that wraps a registry hash entry.

```ruby
# frozen_string_literal: true

module Pim
  class Image
    STATUSES = %w[built verified provisioned published].freeze

    attr_reader :id, :profile, :arch, :path, :iso, :status, :build_time,
                :cache_key, :size, :parent_id, :label, :provisioned_with,
                :provisioned_at, :published_at, :deployments

    def initialize(data)
      @id = data['id']
      @profile = data['profile']
      @arch = data['arch']
      @path = data['path']
      @iso = data['iso']
      @status = data['status'] || 'built'
      @build_time = data['build_time']
      @cache_key = data['cache_key']
      @size = data['size']
      @parent_id = data['parent_id']
      @label = data['label']
      @provisioned_with = data['provisioned_with']
      @provisioned_at = data['provisioned_at']
      @published_at = data['published_at']
      @deployments = data['deployments'] || []
    end

    def golden?
      parent_id.nil?
    end

    def overlay?
      !golden? && !published?
    end

    def published?
      status == 'published'
    end

    def exists?
      path && File.exist?(path)
    end

    def filename
      path ? File.basename(path) : nil
    end

    # Human-readable size
    def human_size
      return nil unless size
      if size > 1_073_741_824
        format("%.1fG", size.to_f / 1_073_741_824)
      elsif size > 1_048_576
        format("%.1fM", size.to_f / 1_048_576)
      else
        format("%.1fK", size.to_f / 1024)
      end
    end

    # Time since build in human-readable form
    def age
      return nil unless build_time
      seconds = Time.now - Time.parse(build_time)
      if seconds < 3600
        "#{(seconds / 60).to_i}m ago"
      elsif seconds < 86400
        "#{(seconds / 3600).to_i}h ago"
      else
        "#{(seconds / 86400).to_i}d ago"
      end
    end

    def to_h
      {
        'id' => id, 'profile' => profile, 'arch' => arch, 'path' => path,
        'iso' => iso, 'status' => status, 'build_time' => build_time,
        'cache_key' => cache_key, 'size' => size, 'parent_id' => parent_id,
        'label' => label, 'provisioned_with' => provisioned_with,
        'provisioned_at' => provisioned_at, 'published_at' => published_at,
        'deployments' => deployments
      }.compact
    end
  end
end
```

### Step 3: Evolve Registry to v2 with auto-migration

**File:** `lib/pim/services/registry.rb`

The key changes:

1. Registry version bumps to 2
2. Each image entry gains: `id`, `status`, `parent_id`, `label`, `provisioned_with`, `provisioned_at`, `published_at`
3. v1 entries are auto-migrated on load (add missing fields with sensible defaults)
4. Images are returned as `Image` objects, not raw hashes
5. New methods: `register_provisioned`, `update_status`, `all_images`

```ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'time'

module Pim
  class Registry
    CURRENT_VERSION = 2

    attr_reader :registry_path

    def initialize(image_dir: nil)
      @image_dir = File.expand_path(image_dir || Pim.config.image_dir)
      @registry_path = File.join(@image_dir, 'registry.yml')
      @data = load_and_migrate
    end

    # --- Query ---

    # All images as Image objects, sorted by build_time desc
    def all
      raw_images.map { |_k, v| Image.new(v) }
                .sort_by { |i| i.build_time || '' }
                .reverse
    end

    # Find image by id, returns Image or nil
    def find(id)
      entry = raw_images[id]
      entry ? Image.new(entry) : nil
    end

    # Find image by id, raises if not found
    def find!(id)
      find(id) || raise("Image '#{id}' not found in registry")
    end

    # --- Registration ---

    # Register a golden image (from build pipeline)
    def register(profile:, arch:, path:, iso:, cache_key:, build_time: nil, status: 'built')
      id = image_key(profile, arch)
      build_time ||= Time.now.utc.iso8601

      entry = {
        'id' => id,
        'profile' => profile,
        'arch' => arch,
        'path' => path,
        'filename' => File.basename(path),
        'iso' => iso,
        'cache_key' => cache_key,
        'build_time' => build_time,
        'size' => File.exist?(path) ? File.size(path) : nil,
        'status' => status,
        'parent_id' => nil,
        'label' => nil,
        'provisioned_with' => nil,
        'provisioned_at' => nil,
        'published_at' => nil,
        'deployments' => []
      }

      raw_images[id] = entry
      save_registry
      Image.new(entry)
    end

    # Register a provisioned image (from vm run --run --label)
    def register_provisioned(parent_id:, label:, path:, script:, arch: nil, profile: nil)
      parent = find!(parent_id)

      id = "#{parent.id}-#{label}"
      entry = {
        'id' => id,
        'profile' => profile || parent.profile,
        'arch' => arch || parent.arch,
        'path' => path,
        'filename' => File.basename(path),
        'iso' => parent.iso,
        'cache_key' => parent.cache_key,
        'build_time' => parent.build_time,
        'size' => File.exist?(path) ? File.size(path) : nil,
        'status' => 'provisioned',
        'parent_id' => parent_id,
        'label' => label,
        'provisioned_with' => script,
        'provisioned_at' => Time.now.utc.iso8601,
        'published_at' => nil,
        'deployments' => []
      }

      raw_images[id] = entry
      save_registry
      Image.new(entry)
    end

    # --- Status transitions ---

    def update_status(id, status)
      entry = raw_images[id]
      return nil unless entry

      entry['status'] = status
      entry['published_at'] = Time.now.utc.iso8601 if status == 'published'
      entry['size'] = File.size(entry['path']) if entry['path'] && File.exist?(entry['path'])
      save_registry
      Image.new(entry)
    end

    # --- Deployment tracking ---

    def record_deployment(id, target:, target_type:, metadata: {})
      entry = raw_images[id]
      return nil unless entry

      deployment = {
        'target' => target,
        'target_type' => target_type,
        'deployed_at' => Time.now.utc.iso8601
      }.merge(metadata)

      entry['deployments'] ||= []
      entry['deployments'] << deployment
      save_registry
      deployment
    end

    # --- Removal ---

    def delete(id)
      entry = raw_images.delete(id)
      save_registry if entry
      entry ? Image.new(entry) : nil
    end

    # --- Cache checks (backward compat with build pipeline) ---

    def cached?(profile:, arch:, cache_key:)
      id = image_key(profile, arch)
      entry = raw_images[id]
      return false unless entry
      return false unless entry['cache_key'] == cache_key
      return false unless entry['path'] && File.exist?(entry['path'])
      true
    end

    # --- Cleanup ---

    def clean_orphaned
      removed = []
      raw_images.each do |id, entry|
        unless entry['path'] && File.exist?(entry['path'])
          removed << id
        end
      end
      removed.each { |id| raw_images.delete(id) }
      save_registry unless removed.empty?
      removed
    end

    # --- Legacy compatibility ---
    # These methods maintain the interface used by BuildManager

    # Legacy: find by profile+arch (returns raw hash for BuildManager compat)
    def find_legacy(profile:, arch:)
      id = image_key(profile, arch)
      raw_images[id]
    end

    # Legacy: list as array of hashes
    def list(long: false)
      all.map do |img|
        {
          key: img.id, profile: img.profile, arch: img.arch,
          filename: img.filename, build_time: img.build_time,
          size: img.size, path: img.path, exists: img.exists?
        }
      end
    end

    # Legacy: unregister by profile+arch
    def unregister(profile:, arch:)
      id = image_key(profile, arch)
      entry = raw_images.delete(id)
      save_registry if entry
      entry
    end

    private

    def raw_images
      @data['images'] ||= {}
    end

    def image_key(profile, arch)
      "#{profile}-#{arch}"
    end

    def load_and_migrate
      data = load_registry
      migrate_v1_to_v2!(data) if data['version'].nil? || data['version'] < CURRENT_VERSION
      data
    end

    def migrate_v1_to_v2!(data)
      data['version'] = CURRENT_VERSION
      images = data['images'] || {}

      images.each do |id, entry|
        # Add missing v2 fields with sensible defaults
        entry['id'] ||= id
        entry['status'] ||= 'built'
        entry['parent_id'] ||= nil
        entry['label'] ||= nil
        entry['provisioned_with'] ||= nil
        entry['provisioned_at'] ||= nil
        entry['published_at'] ||= nil
        entry['deployments'] ||= []
      end

      save_registry
    end

    def load_registry
      return default_registry unless File.exist?(@registry_path)

      data = YAML.load_file(@registry_path)
      return default_registry unless data.is_a?(Hash)
      data
    rescue Psych::SyntaxError => e
      warn "Warning: Failed to parse registry: #{e.message}"
      default_registry
    end

    def save_registry
      FileUtils.mkdir_p(@image_dir)
      File.write(@registry_path, YAML.dump(@data))
    end

    def default_registry
      { 'version' => CURRENT_VERSION, 'images' => {} }
    end
  end
end
```

### Step 4: Update BuildManager to use new Registry API

**File:** `lib/pim/build/manager.rb`

The build pipeline currently calls `registry.register(profile:, arch:, ...)`. This still works — the method signature is unchanged. But we need to make sure the build pipeline:

1. Uses `find_legacy` where it currently accesses the hash directly
2. Sets status to `'built'` on register (already the default)

Search for all `Registry.new` and `.find(profile:, arch:)` calls in the build pipeline and update to use `find_legacy` or the new `find(id)` API. The key files:

- `lib/pim/build/manager.rb` — uses `registry.find(profile:, arch:)` → change to `registry.find_legacy(profile:, arch:)`
- `lib/pim/services/verifier.rb` — uses `registry.find(profile:, arch:)` → change to `registry.find_legacy(profile:, arch:)`
- `lib/pim/services/vm_runner.rb` — uses `registry.find(profile:, arch:)` → change to `registry.find_legacy(profile:, arch:)`
- `lib/pim/commands/builds_command.rb` (Clean, Status) — uses `registry.list` and `registry.unregister` → already compatible

### Step 5: Update Verifier to set status to 'verified'

**File:** `lib/pim/services/verifier.rb`

After a successful verification, update the image status:

```ruby
# After verification passes, in the verify method:
if result.success
  registry = Pim::Registry.new
  id = "#{@profile.id}-#{@arch}"
  registry.update_status(id, 'verified')
end
```

### Step 6: Require `pim/image.rb` in main module

**File:** `lib/pim.rb`

Add: `require_relative "pim/image"` after the config require.

## Test Spec

### Unit tests

**File:** `spec/image_spec.rb`

- `Image.new(data)` populates all attributes from hash
- `#golden?` returns true when `parent_id` is nil
- `#overlay?` returns true when parent_id present and not published
- `#published?` returns true when status is 'published'
- `#human_size` formats bytes correctly (K, M, G)
- `#age` returns human-readable time strings

**File:** `spec/services/registry_spec.rb` (rewrite/extend)

- v1 registry auto-migrates to v2 on load (adds missing fields)
- `#register` creates entry with status 'built' and no parent
- `#register_provisioned` creates entry with parent_id, label, script, status 'provisioned'
- `#find(id)` returns Image object
- `#find!(id)` raises for missing id
- `#all` returns sorted Image array
- `#update_status` transitions status and records published_at
- `#record_deployment` appends to deployments array
- `#delete` removes entry and returns Image
- `#cached?` still works for build pipeline
- `#find_legacy` returns raw hash for backward compat
- `#clean_orphaned` removes entries with missing files

**File:** `spec/config_spec.rb` (extend)

- `config.images.require_label` defaults to true
- `config.images.auto_publish` defaults to false
- Block syntax works: `config.images { |i| i.require_label = false }`

### Manual verification

```bash
# Build an image, check registry
pim build run default-arm64
pim console
> Pim::Registry.new.all.map(&:status)
# => ["built"]

# Verify, check status update
pim build verify default-arm64
pim console
> Pim::Registry.new.find("default-arm64").status
# => "verified"

# Check v1 migration (if you have an existing registry)
# Back up registry.yml, check it has version: 2 after any pim command
```

## Verification

- [ ] Existing v1 registry.yml auto-migrates to v2 on first load
- [ ] `pim build run` registers image with status 'built'
- [ ] `pim build verify` updates status to 'verified'
- [ ] `Registry#find("default-arm64")` returns an Image object
- [ ] `Registry#register_provisioned` creates child image with lineage
- [ ] `config.images.require_label` is configurable in pim.rb
- [ ] All existing build/verify/vm specs still pass
- [ ] `bundle exec rspec` passes
