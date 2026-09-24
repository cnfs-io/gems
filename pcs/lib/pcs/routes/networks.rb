# frozen_string_literal: true

# :nodoc:
module Pcs
  # The site's networks at /networks, and `pcs networks list|show|...`.
  class NetworksResource < Termino::Resource
    model Network

    field :name
    field :subnet
    field :gateway
    field :dns_resolvers
    field :primary, :boolean
    field :dhcp_start
    field :dhcp_end
  end

  App.resource NetworksResource
end
