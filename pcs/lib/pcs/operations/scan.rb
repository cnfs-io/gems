# frozen_string_literal: true

module Pcs
  module Operations
    # Finds what answers on the site's networks (an nmap ping scan) and
    # records it. A machine already known (by MAC, else by IP) gets its current
    # address; anything else becomes a discovered host with one interface.
    # The scan itself runs even in a dry run: it only reads the network.
    class Scan < Termino::Operation
      Summary = Data.define(:added, :updated, :unchanged)

      def initialize(networks: Network.all.to_a, nmap: nil, **)
        super(**)
        @networks = networks
        @nmap = nmap || Adapters::Nmap.new(sudo: Pcs.settings.scan.sudo)
      end

      private

      def perform
        counts = Hash.new(0)
        @networks.each do |network|
          log "scanning #{network.name} (#{network.subnet})"
          @nmap.scan(network.subnet).each { |found| counts[record(found, network)] += 1 }
        end
        Summary.new(counts[:added], counts[:updated], counts[:unchanged]).tap { |summary| report(summary) }
      end

      def report(summary)
        added, updated = dry_run? ? ["would add", "would update"] : %w[added updated]
        log "#{added} #{summary.added}, #{updated} #{summary.updated}, #{summary.unchanged} unchanged"
      end

      # :added, :updated or :unchanged
      def record(found, network)
        iface = (found.mac && Interface.find_by(mac: found.mac)) || Interface.with_ip(found.ip)
        return add(found, network) unless iface

        changes = changes(iface, found)
        return :unchanged if changes.empty?

        step("update #{iface.host&.name || "interface #{iface.id}"}: #{describe(changes)}") { iface.update!(changes) }
        :updated
      end

      # What the scan says that the interface doesn't (nmap only knows MACs
      # when run as root, so a missing one never clears what's recorded).
      def changes(iface, found)
        changes = { mac: found.mac, vendor: found.vendor }
        # Its configured address answering is expected, not a new discovery.
        changes[:discovered_ip] = found.ip unless iface.configured_ip == found.ip
        changes.compact.reject { |name, value| iface.public_send(name) == value }
      end

      def add(found, network)
        hostname = hostname(found)
        step("add host #{hostname || found.ip} (#{[found.ip, found.mac, found.vendor].compact.join(", ")})") do
          host = Host.create!(hostname:)
          Interface.create!(host_id: host.id, network_id: network.id, mac: found.mac, vendor: found.vendor,
                            discovered_ip: found.ip)
        end
        :added
      end

      # The reverse-DNS name nmap found, as a hostname if it's a free DNS label.
      def hostname(found)
        name = found.hostname.to_s.split(".").first.to_s.downcase
        name if name.match?(Host::HOSTNAME) && !Host.exists?(hostname: name)
      end

      def describe(changes)
        changes.map { |name, value| "#{name} #{value}" }.join(", ")
      end
    end
  end
end
