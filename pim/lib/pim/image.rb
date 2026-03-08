# frozen_string_literal: true

require 'time'

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
