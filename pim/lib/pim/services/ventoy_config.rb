# frozen_string_literal: true

require 'pathname'

module Pim
  # Configuration loader for ventoy — delegates to Pim.config.ventoy
  class VentoyConfig
    def version
      Pim.config.ventoy.version
    end

    def dir
      Pim.config.ventoy.dir
    end

    def file
      Pim.config.ventoy.file
    end

    def url
      Pim.config.ventoy.url
    end

    def checksum
      Pim.config.ventoy.checksum
    end

    def device
      Pim.config.ventoy.device
    end

    def ventoy_dir
      Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'ventoy', dir.to_s))
    end

    def mount_point
      Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'ventoy', 'mnt'))
    end

    def iso_dir
      Pathname.new(Pim.config.iso_dir)
    end
  end
end
