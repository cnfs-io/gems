# frozen_string_literal: true

module Pim
  class Config
    attr_accessor :iso_dir, :image_dir,
                  :serve_port, :serve_profile

    def initialize
      @iso_dir = File.join(Pim::XDG_CACHE_HOME, "pim", "isos")
      @image_dir = File.join(Pim::XDG_DATA_HOME, "pim", "images")
      @serve_port = 8080
      @serve_profile = nil
      @images = ImageSettings.new
      @vm = VmSettings.new
      @flat_record_config = nil
    end

    def images
      yield @images if block_given?
      @images
    end

    def vm
      yield @vm if block_given?
      @vm
    end

    def flat_record
      @flat_record_config ||= FlatRecordSettings.new
      yield @flat_record_config if block_given?
      @flat_record_config
    end
  end

  class ImageSettings
    attr_accessor :require_label, :auto_publish

    def initialize
      @require_label = true
      @auto_publish = false
    end
  end

  # Defaults for `pim vm run` (each can be overridden on the command line)
  class VmSettings
    DISKS = %w[clone overlay snapshot].freeze
    NETWORKS = %w[bridged host].freeze

    # disk:    clone    - persistent full copy of the image, reused on later runs (--fresh to re-clone)
    #          overlay  - persistent thin copy (depends on the built image staying put)
    #          snapshot - throwaway, nothing is saved
    # network: bridged  - VM gets an IP on the LAN (sudo on macOS)
    #          host     - NAT, reachable only via ssh -p <port> localhost
    # bridge:  interface to bridge (default: macOS default-route interface, Linux br0)
    # usb:     USB disks to pass through: "VID:PID" (macOS, see `ventoy list`) or device paths
    attr_accessor :disk, :network, :bridge, :usb

    def initialize
      @disk = "clone"
      @network = "bridged"
      @bridge = nil
      @usb = []
    end
  end

  class FlatRecordSettings
    attr_accessor :backend, :id_strategy, :on_missing_file, :merge_strategy, :read_only

    def initialize
      @backend = :yaml
      @id_strategy = :string
      @on_missing_file = :empty
      @merge_strategy = :replace
      @read_only = false
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
