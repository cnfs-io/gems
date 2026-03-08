# frozen_string_literal: true

require 'set'

module Pim
  class Profile < FlatRecord::Base
    source "profiles"
    merge_strategy :deep_merge

    attribute :parent_id, :string
    attribute :hostname, :string
    attribute :username, :string
    attribute :password, :string
    attribute :fullname, :string
    attribute :timezone, :string
    attribute :domain, :string
    attribute :locale, :string
    attribute :keyboard, :string
    attribute :packages, :string
    attribute :authorized_keys_url, :string
    attribute :mirror_host, :string
    attribute :mirror_path, :string
    attribute :http_proxy, :string
    attribute :partitioning_method, :string
    attribute :partitioning_recipe, :string
    attribute :tasksel, :string
    attribute :grub_device, :string

    # Alias for compatibility — Server and other code use .name
    def name
      id
    end

    # Returns resolved attributes (parent chain merged). This is the default view.
    def to_h
      resolved_attributes
    end

    # Returns only directly-set attributes (no parent chain)
    def raw_to_h
      attributes.compact
    end

    def [](key)
      send(key.to_s) if respond_to?(key.to_s)
    end

    # Returns the resolved value for a field, walking up the parent chain
    def resolve(field)
      resolved_attributes[field.to_s]
    end

    # Returns a hash with all attributes resolved through parent chain.
    # Child fields override parent fields.
    def resolved_attributes
      chain = parent_chain
      result = {}
      chain.each do |profile|
        result = result.deep_merge(profile.attributes.compact.except("id", "parent_id"))
      end
      result.merge("id" => id)
    end

    # Returns the parent chain from root to self (oldest ancestor first)
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

    def parent
      return nil unless parent_id
      self.class.find(parent_id)
    end

    def preseed_template(name = nil)
      name ||= id
      find_template('resources/preseeds', "#{name}.cfg.erb") ||
        (name != 'default' && find_template('resources/preseeds', 'default.cfg.erb'))
    end

    def install_template(name = nil)
      name ||= id
      find_template('resources/post_installs', "#{name}.sh") ||
        (name != 'default' && find_template('resources/post_installs', 'default.sh'))
    end

    def verification_script(name = nil)
      name ||= id
      find_template('resources/verifications', "#{name}.sh") ||
        (name != 'default' && find_template('resources/verifications', 'default.sh'))
    end

    private

    def find_template(subdir, filename)
      project_path = Pim.project_dir.join(subdir, filename)
      return project_path.to_s if project_path.exist?
      nil
    end
  end
end
