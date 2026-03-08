# frozen_string_literal: true

module Pcs
  module Service
    class ControlPlane
      def initialize(system_cmd: Adapters::SystemCmd.new)
        @system_cmd = system_cmd
      end

      def apply_static_ip(nm_type, ip:, prefix_len:, gateway:, dns_resolvers:)
        case nm_type
        when :network_manager then apply_static_ip_nmcli(ip, prefix_len, gateway, dns_resolvers)
        when :netplan         then apply_static_ip_netplan(ip, prefix_len, gateway, dns_resolvers)
        when :ifupdown        then apply_static_ip_ifupdown(ip, prefix_len, gateway, dns_resolvers)
        end
      end

      def restart_networking(nm_type)
        case nm_type
        when :network_manager
          @system_cmd.run("nmcli con down 'Wired connection 1' && nmcli con up 'Wired connection 1'", sudo: true)
        when :netplan
          @system_cmd.run("netplan apply", sudo: true)
        when :ifupdown
          @system_cmd.run("systemctl restart networking", sudo: true)
        end
      end

      private

      def apply_static_ip_nmcli(ip, prefix_len, gateway, dns_resolvers)
        conn = "Wired connection 1"
        cmds = [
          "nmcli con mod '#{conn}' ipv4.method manual ipv4.addresses #{ip}/#{prefix_len}",
          "nmcli con mod '#{conn}' ipv4.gateway #{gateway}",
          "nmcli con mod '#{conn}' ipv4.dns '#{dns_resolvers.join(" ")}'",
        ]
        cmds.each { |cmd| @system_cmd.run!(cmd, sudo: true) }
      end

      def apply_static_ip_netplan(ip, prefix_len, gateway, dns_resolvers)
        netplan_config = <<~YAML
          network:
            version: 2
            ethernets:
              eth0:
                dhcp4: false
                addresses:
                  - #{ip}/#{prefix_len}
                routes:
                  - to: default
                    via: #{gateway}
                nameservers:
                  addresses: #{dns_resolvers.inspect}
        YAML
        @system_cmd.file_write("/etc/netplan/99-pcs-static.yaml", netplan_config, sudo: true)
      end

      def apply_static_ip_ifupdown(ip, prefix_len, gateway, dns_resolvers)
        interfaces_config = <<~IFACE
          auto eth0
          iface eth0 inet static
              address #{ip}/#{prefix_len}
              gateway #{gateway}
              dns-nameservers #{dns_resolvers.join(" ")}
        IFACE
        @system_cmd.file_write("/etc/network/interfaces.d/eth0", interfaces_config, sudo: true)
      end
    end
  end
end
