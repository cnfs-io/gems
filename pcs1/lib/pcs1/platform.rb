# frozen_string_literal: true

module Pcs1
  module Platform
    def self.current
      @current ||= case RUBY_PLATFORM
                   when /darwin/ then Darwin.new
                   when /linux/  then Linux.new
                   else raise "Unsupported platform: #{RUBY_PLATFORM}"
                   end
    end

    def self.reset!
      @current = nil
    end
  end
end

require_relative "platform/linux"
require_relative "platform/darwin"
