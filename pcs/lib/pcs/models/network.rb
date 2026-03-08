# frozen_string_literal: true

module Pcs
  class Network < FlatRecord::Base
    source "networks"

    attribute :name, :string
    attribute :subnet, :string
    attribute :gateway, :string
    attribute :dns_resolvers                # Array
    attribute :vlan_id, :integer
    attribute :primary, :boolean, default: false
    attribute :site_id, :string

    belongs_to :site, class_name: "Pcs::Site"
    has_many :interfaces, class_name: "Pcs::Interface", foreign_key: :network_id

    def self.load(site_name = Pcs.site)
      where(site_id: site_name)
    end

    def self.primary(site_name = Pcs.site)
      find_by(site_id: site_name, primary: true)
    end

    def self.find_by_name(name, site_name: Pcs.site)
      find_by(name: name.to_s, site_id: site_name)
    end

    def contains_ip?(ip)
      require "ipaddr"
      IPAddr.new(subnet).include?(ip)
    end
  end
end
