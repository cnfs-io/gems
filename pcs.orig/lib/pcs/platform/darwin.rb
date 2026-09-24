# frozen_string_literal: true

require "pathname"
require_relative "base"

module Pcs
  module Platform
    class Darwin < Base
      def detect_network(system_cmd)
        route_result = system_cmd.run!("route -n get default")
        interface = route_result.stdout[/interface:\s*(\S+)/, 1] || "en0"

        ifconfig = system_cmd.run!("ifconfig #{interface}")
        ip = ifconfig.stdout[/inet\s+(\d+\.\d+\.\d+\.\d+)/, 1]
        netmask_hex = ifconfig.stdout[/netmask\s+(0x\h+)/, 1]
        prefix_len = netmask_hex ? netmask_hex.hex.to_s(2).count("1") : 24
        mac = ifconfig.stdout[/ether\s+([\h:]+)/, 1]

        raise "No IPv4 address found on #{interface}." unless ip

        {
          current_ip: ip,
          mac: mac,
          compute_subnet: compute_subnet_from(ip, prefix_len)
        }
      end

      def detect_timezone(_system_cmd)
        link = File.readlink("/etc/localtime")
        link.sub(%r{.*/zoneinfo/}, "")
      rescue StandardError
        "UTC"
      end

      def available_timezones(_system_cmd)
        dir = Pathname.new("/usr/share/zoneinfo")
        return ["UTC"] unless dir.exist?

        dir.glob("**/*")
           .select(&:file?)
           .map { |p| p.relative_path_from(dir).to_s }
           .reject { |z| z.start_with?("+VERSION", "posix", "right") }
           .sort
      end
    end
  end
end
