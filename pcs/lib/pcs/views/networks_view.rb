# frozen_string_literal: true

module Pcs
  class NetworksView < RestCli::View
    columns       :name, :subnet, :gateway, :primary
    detail_fields :name, :subnet, :gateway, :dns_resolvers, :vlan_id, :primary

    has_many :interfaces, columns: [:name, :ip, :mac, :host_id]

    field_prompt :subnet,  :ask
    field_prompt :gateway, :ask, default: ->(net) {
      base = net.subnet&.split("/")&.first
      return nil unless base
      octets = base.split(".")
      octets[3] = "1"
      octets.join(".")
    }
    field_prompt :dns_resolvers, :ask
  end
end
