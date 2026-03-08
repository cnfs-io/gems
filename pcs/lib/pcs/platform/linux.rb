# frozen_string_literal: true

require_relative "base"

module Pcs
  module Platform
    class Linux < Base
      def detect_network(system_cmd)
        unless system_cmd.command_exists?("ip")
          raise "The 'ip' command is not available."
        end

        interfaces = system_cmd.ip_json("addr show eth0")
        routes = system_cmd.ip_json("route show default")

        iface = interfaces.first
        raise "No active network interface found on eth0." unless iface

        addr_info = iface["addr_info"]&.find { |a| a["family"] == "inet" }
        raise "No IPv4 address found on eth0." unless addr_info

        ip = addr_info["local"]
        prefix_len = addr_info["prefixlen"]
        mac = iface["address"]

        {
          current_ip: ip,
          mac: mac,
          compute_subnet: compute_subnet_from(ip, prefix_len)
        }
      end

      def detect_timezone(_system_cmd)
        result = _system_cmd.run("timedatectl show --property=Timezone --value")
        result.success? ? result.stdout.strip : "UTC"
      end

      def available_timezones(_system_cmd)
        result = _system_cmd.run("timedatectl list-timezones")
        result.success? ? result.stdout.lines.map(&:strip) : ["UTC"]
      end
    end
  end
end
