# frozen_string_literal: true

module Pcs1
  class Config
    attr_accessor :host_defaults, :dnsmasq, :host, :netboot, :log_level, :log_output

    def initialize
      @host_defaults = {}
      @dnsmasq = DnsmasqConfig.new
      @host = HostConfig.new
      @netboot = NetbootConfig.new
      @log_level = :info
      @log_output = $stdout
    end
  end

  class HostConfig
    attr_accessor :wait_attempts, :wait_interval

    def initialize
      @wait_attempts = 30
      @wait_interval = 5
    end
  end

  class DnsmasqConfig
    attr_accessor :config_path, :interface, :lease_time,
                  :range_start_octet, :range_end_octet

    def initialize
      @config_path = "/etc/dnsmasq.d/pcs.conf"
      @interface = "eth0"
      @lease_time = "12h"
      @range_start_octet = 100
      @range_end_octet = 200
    end
  end

  class NetbootConfig
    attr_accessor :image, :netboot_dir,
                  :tftp_port, :http_port, :web_port,
                  :boot_file_bios, :boot_file_efi, :boot_file_arm64

    def initialize
      @image = "docker.io/netbootxyz/netbootxyz"
      @netboot_dir = "/opt/pcs/netboot"
      @tftp_port = 69
      @http_port = 8080
      @web_port = 3000
      @boot_file_bios = "netboot.xyz.kpxe"
      @boot_file_efi = "netboot.xyz.efi"
      @boot_file_arm64 = "netboot.xyz-arm64.efi"
    end
  end
end
