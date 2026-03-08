# frozen_string_literal: true

module Pcs
  module Platform
    class Base
      # Detect the current network configuration.
      # Returns a Hash with keys:
      #   :current_ip      - String, the host's IPv4 address
      #   :mac             - String, the MAC address of the active interface
      #   :compute_subnet  - String, CIDR notation (e.g., "10.0.10.0/24")
      def detect_network(system_cmd)
        raise NotImplementedError, "#{self.class}#detect_network not implemented"
      end

      # Returns the current system timezone as a String (e.g., "Asia/Singapore").
      def detect_timezone(system_cmd)
        raise NotImplementedError, "#{self.class}#detect_timezone not implemented"
      end

      # Returns an Array<String> of available timezone names.
      def available_timezones(system_cmd)
        raise NotImplementedError, "#{self.class}#available_timezones not implemented"
      end

      # Detect the local subnet from the primary interface.
      # Returns a CIDR string like "10.0.10.0/24".
      def local_subnet(system_cmd)
        detect_network(system_cmd)[:compute_subnet]
      end

      private

      def compute_subnet_from(ip, prefix_len)
        octets = ip.split(".").map(&:to_i)
        "#{octets[0]}.#{octets[1]}.#{octets[2]}.0/#{prefix_len}"
      end
    end
  end
end
