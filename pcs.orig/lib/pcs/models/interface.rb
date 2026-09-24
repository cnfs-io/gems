# frozen_string_literal: true

module Pcs
  class Interface < FlatRecord::Base
    source "interfaces"

    attribute :name, :string         # NIC name: enp2s0, eth0 (nil for discovered)
    attribute :mac, :string
    attribute :ip, :string
    attribute :host_id, :string
    attribute :network_id, :string
    attribute :site_id, :string

    belongs_to :host, class_name: "Pcs::Host"
    belongs_to :network, class_name: "Pcs::Network"

    def self.load(site_name = Pcs.site)
      where(site_id: site_name)
    end

    def network_name
      network&.name
    end
  end
end
