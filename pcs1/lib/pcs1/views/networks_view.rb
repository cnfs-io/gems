# frozen_string_literal: true

module Pcs1
  class NetworksView < RestCli::View
    columns       :id, :name, :subnet, :gateway, :primary
    detail_fields :id, :name, :subnet, :gateway, :dns_resolvers, :primary, :site_id

    has_many :interfaces, columns: %i[name ip mac host_id]

    field_prompt :name,          :ask
    field_prompt :subnet,        :ask
    field_prompt :gateway,       :ask, default: lambda { |net|
      base = net.subnet&.split("/")&.first
      return nil unless base

      octets = base.split(".")
      octets[3] = "1"
      octets.join(".")
    }
    field_prompt :dns_resolvers, :ask
    field_prompt :primary,       :select, choices: %w[true false]
  end
end
