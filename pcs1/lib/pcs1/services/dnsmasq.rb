# frozen_string_literal: true

require "erb"
require "pathname"

module Pcs1
  class Dnsmasq
    TEMPLATE_PATH = Pathname.new(__dir__).join("..", "templates", "dnsmasq.conf.erb")

    # Reconcile: render config from current data, diff against disk, restart if changed.
    def self.reconcile!(exclude_ips: [])
      new_config = render_config(exclude_ips: exclude_ips)
      config_path = Pathname(Pcs1.config.dnsmasq.config_path)

      current_config = config_path.exist? ? config_path.read : ""

      if new_config == current_config
        puts "  dnsmasq: config unchanged, skipping restart"
        return false
      end

      write_config!(config_path, new_config)
      restart!
      true
    end

    def self.start!
      system_cmd("sudo systemctl enable dnsmasq")
      system_cmd("sudo systemctl start dnsmasq")
      puts "  dnsmasq: enabled and started"
    end

    def self.stop!
      system_cmd("sudo systemctl stop dnsmasq")
      system_cmd("sudo systemctl disable dnsmasq")
      puts "  dnsmasq: stopped and disabled"
    end

    def self.restart!
      system_cmd("sudo systemctl restart dnsmasq")
      puts "  dnsmasq: restarted"
    end

    def self.status
      result = `systemctl is-active dnsmasq 2>/dev/null`.strip
      result.empty? ? "unknown" : result
    end

    def self.render_config(exclude_ips: [])
      site = Pcs1.site
      config = Pcs1.config.dnsmasq
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

      range_start = [*octets[0..2], config.range_start_octet.to_s].join(".")
      range_end = [*octets[0..2], config.range_end_octet.to_s].join(".")
      gateway = network.gateway
      dns_servers = (network.dns_resolvers || [gateway]).join(",")

      reservations = build_reservations(site, exclude_ips: exclude_ips)

      template = ERB.new(TEMPLATE_PATH.read, trim_mode: "-")
      template.result_with_hash(
        interface: config.interface,
        range_start: range_start,
        range_end: range_end,
        netmask: netmask,
        lease_time: config.lease_time,
        gateway: gateway,
        dns_servers: dns_servers,
        ops_ip: ops_ip,
        reservations: reservations
      )
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

    private

    def self.write_config!(config_path, content)
      config_path = Pathname(config_path)
      IO.popen(["sudo", "tee", config_path.to_s], "w", out: File::NULL) { |io| io.write(content) }
      puts "  dnsmasq: wrote #{config_path}"
    end

    def self.system_cmd(cmd)
      system(cmd) || raise("Command failed: #{cmd}")
    end

    def self.prefix_to_netmask(prefix_len)
      mask = (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF
      [mask].pack("N").unpack("C4").join(".")
    end
  end
end
