# frozen_string_literal: true

module Pcs
  class Role < FlatRecord::Base
    source "roles"
    read_only true

    def self.hierarchy_child? = false

    attribute :types
    attribute :ip_base, :integer

    def valid_types
      case types
      when Array then types.map(&:to_s)
      when String then types.split(",").map(&:strip)
      else []
      end
    end

    def self.names
      all.map(&:id)
    end

    def self.types_for(role_name)
      find(role_name.to_s).valid_types
    rescue FlatRecord::RecordNotFound
      []
    end

    def self.octet_for(role_name, index = 0)
      role = find(role_name.to_s)
      role.ip_base + index
    end
  end
end
