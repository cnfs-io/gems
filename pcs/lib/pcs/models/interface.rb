# frozen_string_literal: true

module Pcs
  # A host's network interface. The IP it was found at (discovered_ip) and the
  # one it's configured to use (configured_ip) differ until it's installed.
  class Interface < FlatRecord::Base
    file_layout :individual
    source "interfaces"

    MAC = /\A\h{2}(:\h{2}){5}\z/

    attribute :name, :string
    attribute :mac, :string
    attribute :discovered_ip, :string
    attribute :configured_ip, :string
    attribute :vendor, :string # from the MAC's OUI, as nmap reports it
    attribute :host_id, :string
    attribute :network_id, :string

    belongs_to :host, class_name: "Pcs::Host"
    belongs_to :network, class_name: "Pcs::Network"

    validates :mac, format: { with: MAC, message: "must look like aa:bb:cc:dd:ee:ff" }, allow_blank: true
    validates :mac, uniqueness: { case_sensitive: false }, allow_blank: true
    validate :configured_ip_in_network

    def mac=(value)
      super(value&.strip&.downcase)
    end

    # Where to reach the host now: its configured IP once it has one.
    def reachable_ip
      configured_ip.presence || discovered_ip
    end

    # The interface known by this address (found at, or configured with).
    def self.with_ip(ip)
      all.find { |iface| iface.discovered_ip == ip || iface.configured_ip == ip }
    end

    private

    def configured_ip_in_network
      return if configured_ip.blank? || network.nil? || network.contains?(configured_ip)

      errors.add(:configured_ip, "is not in #{network.name} (#{network.subnet})")
    end
  end
end
