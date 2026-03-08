# frozen_string_literal: true

require 'digest'
require 'json'

module Pim
  # Content-based cache key generation
  class CacheManager
    def initialize(project_dir: Dir.pwd)
      @project_dir = project_dir
    end

    # Generate cache key from profile, scripts, and ISO
    def cache_key(profile_data:, scripts:, iso_checksum:, arch:)
      components = []

      # Profile data (sorted for consistency)
      profile_json = JSON.generate(sort_hash(profile_data))
      components << Digest::SHA256.hexdigest(profile_json)

      # Scripts content
      scripts.each do |script_path|
        if File.exist?(script_path)
          components << Digest::SHA256.file(script_path).hexdigest
        end
      end

      # ISO checksum
      components << iso_checksum.to_s.sub(/^sha\d+:/, '')

      # Architecture
      components << arch

      # Combined hash
      Digest::SHA256.hexdigest(components.join(':'))[0..15]
    end

    # Check if a cached image exists
    def cached?(profile:, arch:, cache_key:)
      registry = Pim::Registry.new(image_dir: Pim.config.image_dir)
      registry.cached?(profile: profile, arch: arch, cache_key: cache_key)
    end

    # Get cached image path if valid
    def cached_image(profile:, arch:, cache_key:)
      registry = Pim::Registry.new(image_dir: Pim.config.image_dir)
      entry = registry.find(profile: profile, arch: arch)

      return nil unless entry
      return nil unless entry['cache_key'] == cache_key
      return nil unless entry['path'] && File.exist?(entry['path'])

      entry['path']
    end

    private

    def sort_hash(obj)
      case obj
      when Hash
        obj.sort.to_h.transform_values { |v| sort_hash(v) }
      when Array
        obj.map { |v| sort_hash(v) }
      else
        obj
      end
    end
  end
end
