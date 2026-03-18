# frozen_string_literal: true

module Pcs1
  class Config
    attr_accessor :host_defaults, :dnsmasq, :host

    def initialize
      @host_defaults = {}
      @dnsmasq = DnsmasqConfig.new
      @host = HostConfig.new
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
end
