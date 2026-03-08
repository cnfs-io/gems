# frozen_string_literal: true

module Pcs
  module Platform
    def self.current
      @current ||= load_platform
    end

    def self.reset!
      @current = nil
    end

    def self.load_platform
      case RUBY_PLATFORM
      when /darwin/
        require_relative "platform/darwin"
        Darwin.new
      when /linux/
        require_relative "platform/linux"
        Linux.new
      else
        raise "Unsupported platform: #{RUBY_PLATFORM}"
      end
    end

    private_class_method :load_platform
  end
end

require_relative "platform/arch"
require_relative "platform/os"
