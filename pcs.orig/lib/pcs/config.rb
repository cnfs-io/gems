# frozen_string_literal: true

module Pcs
  class Config
    attr_accessor :serve_port, :default_root_password, :default_locale, :default_packages

    def initialize
      @serve_port = nil
      @flat_record_config = nil
      @networking_config = nil
      @default_root_password = "changeme123!"
      @default_locale = "en-us"
      @default_packages = "openssh-server curl sudo"
    end

    def flat_record
      @flat_record_config ||= FlatRecordSettings.new
      yield @flat_record_config if block_given?
      @flat_record_config
    end

    def networking
      @networking_config ||= NetworkingSettings.new
      yield @networking_config if block_given?
      @networking_config
    end

    def service
      @service_config ||= ServiceSettings.new
      yield @service_config if block_given?
      @service_config
    end

    def discovery
      @discovery_config ||= DiscoverySettings.new
      yield @discovery_config if block_given?
      @discovery_config
    end
  end

  class NetworkingSettings
    attr_accessor :dns_fallback_resolvers

    def initialize
      @dns_fallback_resolvers = ["1.1.1.1", "8.8.8.8"]
    end
  end

  class FlatRecordSettings
    attr_accessor :backend, :id_strategy, :on_missing_file, :merge_strategy, :read_only,
                  :hierarchy_model, :hierarchy_key

    def initialize
      @backend = :yaml
      @id_strategy = :integer
      @on_missing_file = :empty
      @merge_strategy = :replace
      @read_only = false
      @hierarchy_model = nil
      @hierarchy_key = :name
    end

    def hierarchy(model:, key: :name)
      @hierarchy_model = model
      @hierarchy_key = key
    end
  end

  class DnsmasqSettings
    attr_accessor :proxy, :config_dir

    def initialize
      @proxy = true
      @config_dir = Pathname.new("/etc/dnsmasq.d")
    end
  end

  class NetbootSettings
    attr_accessor :image, :ipxe_timeout, :default_os, :netboot_dir

    def initialize
      @image = "docker.io/netbootxyz/netbootxyz"
      @ipxe_timeout = 10
      @default_os = "debian-trixie"
      @netboot_dir = Pathname.new("/opt/pcs/netboot")
    end
  end

  class ProxmoxSettings
    attr_accessor :default_preseed_interface, :default_preseed_device,
                  :reboot_initial_wait, :reboot_poll_interval, :reboot_max_attempts,
                  :web_port

    def initialize
      @default_preseed_interface = "enp1s0"
      @default_preseed_device = "/dev/sda"
      @reboot_initial_wait = 30
      @reboot_poll_interval = 15
      @reboot_max_attempts = 20
      @web_port = 8006
    end
  end

  class DiscoverySettings
    attr_accessor :users, :passwords

    def initialize
      @users = %w[root admin pi]
      @passwords = %w[changeme123! root admin raspberry]
    end
  end

  class ServiceSettings
    def dnsmasq
      @dnsmasq_config ||= DnsmasqSettings.new
      yield @dnsmasq_config if block_given?
      @dnsmasq_config
    end

    def netboot
      @netboot_config ||= NetbootSettings.new
      yield @netboot_config if block_given?
      @netboot_config
    end

    def proxmox
      @proxmox_config ||= ProxmoxSettings.new
      yield @proxmox_config if block_given?
      @proxmox_config
    end
  end

  def self.configure
    @config ||= Config.new
    yield @config if block_given?
    @config
  end

  def self.config
    @config || configure
  end
end
