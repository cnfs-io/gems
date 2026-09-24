# frozen_string_literal: true

require "rexml/document"

module Pcs
  module Adapters
    # Finds the hosts that answer on a subnet (a ping scan, not a port scan).
    class Nmap
      Found = Data.define(:ip, :mac, :vendor, :hostname)

      def initialize(system: SystemCmd.new, sudo: true)
        @system = system
        @sudo = sudo
      end

      # Hosts up on subnet ("192.168.1.0/24"). MAC addresses need root.
      def scan(subnet)
        argv = ["nmap", "-sn", "-oX", "-", subnet]
        argv = ["sudo", "-n", *argv] if @sudo # -n: fail rather than prompt for a password
        result = @system.run(*argv)
        raise Pcs::Error, failure(result) unless result.success?

        self.class.parse(result.stdout)
      end

      # What went wrong, and what to do about it.
      def failure(result)
        hint = if result.status == 127 || result.stderr.include?("command not found")
                 "install nmap"
               elsif @sudo && result.stderr.include?("password is required")
                 "allow passwordless sudo for nmap (it needs root to read MAC addresses), " \
                   "or set `settings.scan.sudo = false` in pcs.rb to scan without MACs"
               end
        [result.message, hint].compact.join("; ")
      end

      def self.parse(xml)
        REXML::Document.new(xml).get_elements("//host").filter_map { |host| found(host) }
      end

      # A host element that's up and has an IPv4 address, as Found.
      def self.found(host)
        return unless attributes(host.elements["status"])["state"] == "up"

        addresses = addresses(host)
        return unless (ip = addresses.dig("ipv4", "addr"))

        mac = addresses.fetch("mac", {})
        Found.new(ip:, mac: mac["addr"]&.downcase, vendor: mac["vendor"],
                  hostname: attributes(host.elements["hostnames/hostname"])["name"])
      end

      # A host's addresses by type: { "ipv4" => {"addr" => ...}, "mac" => {...} }
      def self.addresses(host)
        host.get_elements("address").to_h { |a| attributes(a).then { |h| [h["addrtype"], h] } }
      end

      # An element's attributes as a plain Hash ({} for a missing element).
      def self.attributes(element)
        {}.tap { |h| element&.attributes&.each { |name, value| h[name] = value } }
      end
    end
  end
end
