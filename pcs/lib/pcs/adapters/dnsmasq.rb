# frozen_string_literal: true

require "erb"
require "pathname"

module Pcs
  module Adapters
    class Dnsmasq
      TEMPLATE_PATH = Pathname.new(__dir__).join("..", "templates", "dnsmasq", "pcs-pxe-proxy.conf.erb")

      def self.config_path(project_name)
        Pcs.config.service.dnsmasq.config_dir / "#{project_name}.conf"
      end

      def self.write_config(servers_subnet:, gateway:, ops_ip:, project_name:, proxy:, system_cmd:)
        subnet_base, prefix_str = servers_subnet.split("/")
        netmask = prefix_to_netmask(prefix_str.to_i)
        octets = subnet_base.split(".")

        template = TEMPLATE_PATH.read
        result = ERB.new(template, trim_mode: "-").result_with_hash(
          proxy: proxy,
          servers_subnet_base: subnet_base,
          netmask: netmask,
          gateway: gateway,
          ops_ip: ops_ip,
          dhcp_range_start: [*octets[0..2], "100"].join("."),
          dhcp_range_end: [*octets[0..2], "200"].join(".")
        )

        system_cmd.file_write(config_path(project_name), result, sudo: true)
      end

      def self.reload!(system_cmd:)
        system_cmd.service("reload", "dnsmasq")
      end

      def self.prefix_to_netmask(prefix_len)
        mask = (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF
        [mask].pack("N").unpack("C4").join(".")
      end
      private_class_method :prefix_to_netmask
    end
  end
end
