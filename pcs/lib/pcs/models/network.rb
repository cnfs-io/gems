# frozen_string_literal: true

require "ipaddr"

module Pcs
  # An IPv4 network at the site, e.g. the LAN the control plane is on.
  class Network < FlatRecord::Base
    file_layout :individual
    source "networks"

    attribute :name, :string
    attribute :subnet, :string # CIDR: 192.168.1.0/24
    attribute :gateway, :string
    attribute :dns_resolvers, :string # comma or space separated
    attribute :primary, :boolean, default: false
    # The address pool dnsmasq hands out in "dhcp" mode (unused in "proxy").
    attribute :dhcp_start, :string
    attribute :dhcp_end, :string
    attribute :site_id, :string

    belongs_to :site, class_name: "Pcs::Site"
    before_validation { self.site_id ||= Site.first&.id }
    has_many :interfaces, class_name: "Pcs::Interface", foreign_key: :network_id, dependent: :restrict_with_error

    validates :name, presence: true, uniqueness: true
    validates :subnet, presence: true
    validate :subnet_is_cidr
    validate :gateway_inside_subnet
    validate :dhcp_range_inside_subnet

    def self.primary
      find_by(primary: true) || first
    end

    # [[label, id], ...] for choosing a network in forms.
    def self.choices
      all.map { |network| ["#{network.name} (#{network.subnet})", network.id] }
    end

    # The network an address is in, if any.
    def self.for_ip(ip)
      all.find { |network| network.contains?(ip) }
    end

    def range
      IPAddr.new(subnet)
    end

    def prefix
      subnet.split("/").last.to_i
    end

    def netmask
      IPAddr.new("255.255.255.255").mask(prefix).to_s
    end

    def contains?(ip)
      range.include?(IPAddr.new(ip.to_s))
    rescue IPAddr::Error
      false
    end

    def dns_list
      dns_resolvers.to_s.split(/[\s,]+/).reject(&:empty?)
    end

    # Resolvers for hosts: the listed ones, else the gateway.
    def nameservers
      dns_list.presence || [gateway].compact
    end

    # The network address (10.0.0.0 of 10.0.0.0/24).
    def address
      range.to_s
    end

    # The control plane's address here, which serves installs on this network.
    def control_plane_ip
      interfaces.find { |iface| iface.host&.cp? && iface.configured_ip.present? }&.configured_ip
    end

    # The control plane's interface name here (what dnsmasq listens on).
    def control_plane_interface
      interfaces.find { |iface| iface.host&.cp? }&.name
    end

    private

    def subnet_is_cidr
      return if subnet.blank?
      return errors.add(:subnet, "must be CIDR, e.g. 192.168.1.0/24") unless subnet.match?(%r{\A[\d.]+/\d{1,2}\z})

      IPAddr.new(subnet)
    rescue IPAddr::Error
      errors.add(:subnet, "is not a valid network")
    end

    def gateway_inside_subnet
      return if gateway.blank? || errors.include?(:subnet) || contains?(gateway)

      errors.add(:gateway, "is not in #{subnet}")
    end

    def dhcp_range_inside_subnet
      return if errors.include?(:subnet)

      %i[dhcp_start dhcp_end].each do |name|
        ip = public_send(name)
        errors.add(name, "is not in #{subnet}") if ip.present? && !contains?(ip)
      end
    end
  end
end
