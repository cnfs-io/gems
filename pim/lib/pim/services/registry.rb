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
    def register(profile:, arch:, path:, iso:, cache_key:, build_time: nil, status: 'built', metadata: {})
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
      }.merge(metadata)

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
    # These methods maintain the interface used by BuildManager, Verifier, VmRunner

    # Legacy: find by profile+arch (returns raw hash)
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
        entry['id'] = id unless entry.key?('id')
        entry['status'] = 'built' unless entry.key?('status')
        entry['parent_id'] = nil unless entry.key?('parent_id')
        entry['label'] = nil unless entry.key?('label')
        entry['provisioned_with'] = nil unless entry.key?('provisioned_with')
        entry['provisioned_at'] = nil unless entry.key?('provisioned_at')
        entry['published_at'] = nil unless entry.key?('published_at')
        entry['deployments'] = [] unless entry.key?('deployments')
      end

      save_registry
    end

    def load_registry
      return default_registry unless File.exist?(@registry_path)

      data = YAML.safe_load_file(@registry_path, permitted_classes: [Time])
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
