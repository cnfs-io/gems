# frozen_string_literal: true

require "ipaddr"

module Pcs1
  class Network < FlatRecord::Base
    source "networks"

    attribute :name, :string
    attribute :subnet, :string
    attribute :gateway, :string
    attribute :dns_resolvers
    attribute :primary, :boolean, default: false
    attribute :site_id, :string

    belongs_to :site, class_name: "Pcs1::Site"
    has_many :interfaces, class_name: "Pcs1::Interface", foreign_key: :network_id

    def contains_ip?(ip)
      IPAddr.new(subnet).include?(ip)
    end

    # Scan the network via nmap. Returns { new:, updated:, unchanged: } counts.
    def scan
      results = nmap_scan(subnet)
      merge_results(results)
    end

    private

    def nmap_scan(subnet)
      require "rexml/document"

      output = `sudo nmap -sn #{subnet} -oX - 2>/dev/null`
      return [] if output.empty?

      doc = REXML::Document.new(output)
      hosts = []

      doc.elements.each("nmaprun/host") do |host_el|
        status = host_el.elements["status"]&.attributes&.[]("state")
        next unless status == "up"

        ip = host_el.elements["address[@addrtype='ipv4']"]&.attributes&.[]("addr")
        mac = host_el.elements["address[@addrtype='mac']"]&.attributes&.[]("addr")

        hosts << { ip: ip, mac: mac&.downcase } if ip
      end

      hosts
    end

    def merge_results(results)
      counts = { new: 0, updated: 0, unchanged: 0 }
      site = self.site

      results.each do |result|
        ip = result[:ip]
        mac = result[:mac]

        # Try to find existing interface by MAC or discovered_ip on this network
        existing_iface = if mac
                           interfaces.detect { |i| i.mac&.downcase == mac.downcase }
                         end
        existing_iface ||= interfaces.detect { |i| i.discovered_ip == ip }

        if existing_iface
          if existing_iface.discovered_ip != ip
            existing_iface.update(discovered_ip: ip, mac: mac)
            counts[:updated] += 1
          elsif mac && existing_iface.mac != mac
            existing_iface.update(mac: mac)
            counts[:updated] += 1
          else
            counts[:unchanged] += 1
          end
        else
          # New host — create Host + Interface with discovered_ip
          host = Pcs1::Host.create(
            status: "discovered",
            site_id: site.id
          )

          Pcs1::Interface.create(
            discovered_ip: ip,
            mac: mac,
            host_id: host.id,
            network_id: self.id
          )

          counts[:new] += 1
        end
      end

      counts
    end
  end
end
