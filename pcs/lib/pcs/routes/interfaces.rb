# frozen_string_literal: true

# :nodoc:
module Pcs
  # Hosts' network interfaces at /interfaces, and `pcs interfaces list|show|...`.
  class InterfacesResource < Termino::Resource
    model Interface

    field :host_id, :select, choices: -> { Host.choices }
    field :network_id, :select, choices: -> { Network.choices }
    field :name
    field :mac
    field :vendor
    field :discovered_ip
    field :configured_ip
  end

  App.resource InterfacesResource
end
