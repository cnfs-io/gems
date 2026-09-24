# frozen_string_literal: true

require "ipaddr"
require "rbconfig"
require "socket"

module Pcs
  # Facts about the machine pcs runs on (the control plane).
  module Local
    Iface = Data.define(:name, :ip, :prefix, :mac) do
      def subnet = "#{IPAddr.new("#{ip}/#{prefix}")}/#{prefix}"
    end

    # Container, VPN and virtual-machine interfaces aren't site networks.
    VIRTUAL = /\A(lo|docker|podman|veth|cni|br-|virbr|vnet|tailscale|wg|tun|tap|utun|bridge|awdl|llw)/

    module_function

    # The machine's IPv4 addresses on real networks.
    def interfaces
      Socket.getifaddrs.select { |ifa| site_address?(ifa) }.map do |ifa|
        prefix = IPAddr.new(ifa.netmask.ip_address).to_i.to_s(2).count("1")
        Iface.new(ifa.name, ifa.addr.ip_address, prefix, mac_for(ifa.name))
      end
    end

    # An IPv4 address on a real network: not loopback, link-local or virtual.
    def site_address?(ifa)
      addr = ifa.addr
      return false unless addr&.ipv4? && ifa.netmask && !addr.ipv4_loopback?

      !ifa.name.match?(VIRTUAL) && !addr.ip_address.start_with?("169.254.")
    end

    def mac_for(name)
      File.read("/sys/class/net/#{name}/address").strip.downcase
    rescue SystemCallError
      nil
    end

    # This machine's name as a DNS label ("Pi's-Lab.local" -> "pi-s-lab").
    def hostname
      Socket.gethostname.split(".").first.downcase.gsub(/[^a-z0-9-]+/, "-").gsub(/\A-+|-+\z/, "")[0, 63]
    end

    def arch
      case RbConfig::CONFIG["host_cpu"]
      when /aarch64|arm64/ then "arm64"
      when /x86_64|amd64/ then "amd64"
      else RbConfig::CONFIG["host_cpu"]
      end
    end

    def timezone
      ENV["TZ"].then { |tz| return tz if tz && !tz.empty? }
      return File.read("/etc/timezone").strip if File.exist?("/etc/timezone")

      File.readlink("/etc/localtime")[%r{zoneinfo/(.+)\z}, 1] || "UTC"
    rescue SystemCallError
      "UTC"
    end
  end
end
