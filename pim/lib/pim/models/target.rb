# frozen_string_literal: true

require "set"

module Pim
  class Target < FlatRecord::Base
    source "targets"
    sti_column :type

    attribute :type, :string
    attribute :parent_id, :string
    attribute :name, :string

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

    def deploy(image_path)
      raise NotImplementedError, "#{self.class.name} must implement #deploy"
    end
  end
end
