# frozen_string_literal: true

require "set"

module Pcs
  class Profile < FlatRecord::Base
      source "profiles"
      read_only true
      merge_strategy :deep_merge

      # Profile uses per-model data_paths (not project hierarchy),
      # so opt out of FlatRecord's hierarchy system.
      def self.hierarchy_child? = false

      # Shared attributes (same as PIM)
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

      # PCS-specific attributes
      attribute :interface, :string
      attribute :device, :string

      def name
        id
      end

      def parent
        return nil unless parent_id
        self.class.find(parent_id)
      end

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
        chain.each do |profile|
          result = result.deep_merge(profile.attributes.compact.except("id", "parent_id"))
        end
        result.merge("id" => id)
      end

      def to_h
        resolved_attributes
      end

      def [](key)
        send(key.to_s) if respond_to?(key.to_s)
      end

      def resolve(field)
        resolved_attributes[field.to_s]
      end
  end
end
