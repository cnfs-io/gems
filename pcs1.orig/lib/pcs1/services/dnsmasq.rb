# frozen_string_literal: true

module Pcs1
  class Dnsmasq < Service
    # Reconcile: render config from current data, diff against disk, restart if changed.
    def self.reconcile!
      new_config = render_config
      config_path = Pathname(Pcs1.config.dnsmasq.config_path)

      current_config = config_path.exist? ? config_path.read : ""

      if new_config == current_config
        logger.info("dnsmasq: config unchanged, skipping restart")
        return false
      end

      sudo_write(config_path, new_config)
      logger.info("dnsmasq: wrote #{config_path}")
      restart!
      true
    end

    def self.start!
      system_cmd("sudo systemctl enable dnsmasq")
      system_cmd("sudo systemctl start dnsmasq")
      logger.info("dnsmasq: enabled and started")
    end

    def self.stop!
      system_cmd("sudo systemctl stop dnsmasq")
      system_cmd("sudo systemctl disable dnsmasq")
      logger.info("dnsmasq: stopped and disabled")
    end

    def self.restart!
      system_cmd("sudo systemctl restart dnsmasq")
      logger.info("dnsmasq: restarted")
    end

    def self.status
      capture("systemctl is-active dnsmasq").then { |r| r.empty? ? "unknown" : r }
    end

    def self.render_config
      site = Pcs1.site
      dnsmasq_config = Pcs1.config.dnsmasq
      netboot_config = Pcs1.config.netboot
      network = site.networks.detect(&:primary)

      raise "No primary network configured" unless network

      # Find the local host's IP on this network — this is the TFTP/DHCP server
      ops_ip = ops_ip_for(network)
      raise "No local host interface found on primary network" unless ops_ip

      subnet_base, prefix_str = network.subnet.split("/")
      prefix_len = prefix_str.to_i
      netmask = prefix_to_netmask(prefix_len)
      octets = subnet_base.split(".")

      range_start = [*octets[0..2], dnsmasq_config.range_start_octet.to_s].join(".")
      range_end = [*octets[0..2], dnsmasq_config.range_end_octet.to_s].join(".")
      gateway = network.gateway
      dns_servers = (network.dns_resolvers || [gateway]).join(",")

      reservations = build_reservations(network)

      render_template("dnsmasq.conf.erb",
                      interface: dnsmasq_config.interface,
                      range_start: range_start,
                      range_end: range_end,
                      netmask: netmask,
                      lease_time: dnsmasq_config.lease_time,
                      gateway: gateway,
                      dns_servers: dns_servers,
                      ops_ip: ops_ip,
                      boot_file_bios: netboot_config.boot_file_bios,
                      boot_file_efi: netboot_config.boot_file_efi,
                      boot_file_arm64: netboot_config.boot_file_arm64,
                      reservations: reservations)
    end

    # Build reservations by iterating the network's interfaces.
    def self.build_reservations(network)
      reservations = []

      network.interfaces.each do |iface|
        next unless iface.mac && iface.configured_ip

        host = iface.host
        next unless host&.hostname

        reservations << {
          mac: iface.mac,
          ip: iface.configured_ip,
          hostname: host.hostname
        }
      end

      reservations
    end

    # Find the local host's configured IP on a given network.
    def self.ops_ip_for(network)
      network.interfaces.each do |iface|
        return iface.configured_ip if iface.host&.local?
      end
      nil
    end

    def self.prefix_to_netmask(prefix_len)
      mask = (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF
      [mask].pack("N").unpack("C4").join(".")
    end
  end
end
