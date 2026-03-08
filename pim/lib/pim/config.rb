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
      @ventoy = VentoySettings.new
      @images = ImageSettings.new
      @flat_record_config = nil
    end

    def images
      yield @images if block_given?
      @images
    end

    def ventoy
      yield @ventoy if block_given?
      @ventoy
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

  class VentoySettings
    attr_accessor :version, :dir, :file, :url, :checksum, :device

    def initialize
      @version = nil
      @dir = nil
      @file = nil
      @url = nil
      @checksum = nil
      @device = nil
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
