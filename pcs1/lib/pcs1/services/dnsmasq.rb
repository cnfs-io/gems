# frozen_string_literal: true

module Pcs1
  class Dnsmasq < Service
    # Reconcile: render config from current data, diff against disk, restart if changed.
    def self.reconcile!(exclude_ips: [])
      new_config = render_config(exclude_ips: exclude_ips)
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

    def self.render_config(exclude_ips: [])
      site = Pcs1.site
      dnsmasq_config = Pcs1.config.dnsmasq
      netboot_config = Pcs1.config.netboot
      network = site.networks.detect(&:primary)

      raise "No primary network configured" unless network

      cp_host = site.hosts.detect { |h| h.role == "cp" }
      raise "No control plane host found" unless cp_host

      cp_iface = cp_host.interfaces.first
      raise "Control plane host has no interface" unless cp_iface

      ops_ip = cp_iface.reachable_ip
      raise "Control plane host has no IP" unless ops_ip

      subnet_base, prefix_str = network.subnet.split("/")
      prefix_len = prefix_str.to_i
      netmask = prefix_to_netmask(prefix_len)
      octets = subnet_base.split(".")

      range_start = [*octets[0..2], dnsmasq_config.range_start_octet.to_s].join(".")
      range_end = [*octets[0..2], dnsmasq_config.range_end_octet.to_s].join(".")
      gateway = network.gateway
      dns_servers = (network.dns_resolvers || [gateway]).join(",")

      reservations = build_reservations(site, exclude_ips: exclude_ips)

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

    def self.build_reservations(site, exclude_ips: [])
      reservations = []

      site.hosts.each do |host|
        next unless host.hostname

        host.interfaces.each do |iface|
          next unless iface.mac && iface.configured_ip
          next if exclude_ips.include?(iface.configured_ip)

          reservations << {
            mac: iface.mac,
            ip: iface.configured_ip,
            hostname: host.hostname
          }
        end
      end

      reservations
    end

    def self.prefix_to_netmask(prefix_len)
      mask = (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF
      [mask].pack("N").unpack("C4").join(".")
    end
  end
end
