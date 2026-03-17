# frozen_string_literal: true

module Pcs1
  class Interface < FlatRecord::Base
    source "interfaces"

    attribute :name, :string          # NIC name: enp2s0, eth0 (set during configure)
    attribute :mac, :string           # MAC address (from scan)
    attribute :discovered_ip, :string # DHCP-assigned IP (from scan)
    attribute :ip, :string            # Static/intended IP (set during configure)
    attribute :host_id, :string
    attribute :network_id, :string

    belongs_to :host, class_name: "Pcs1::Host"
    belongs_to :network, class_name: "Pcs1::Network"

    def configured?
      !ip.nil? && !ip.empty?
    end

    # The best IP to reach this host — static if set, otherwise discovered
    def reachable_ip
      ip || discovered_ip
    end
  end
end
