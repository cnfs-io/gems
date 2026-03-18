# frozen_string_literal: true

require "flat_record"
require "rest_cli"
require "state_machines"
require_relative "pcs1/version"
require_relative "pcs1/config"
require_relative "pcs1/platform"
require_relative "pcs1/application"

# Auto-require all Ruby files under lib/pcs1/ (models, views, commands, etc.)
Dir.glob(File.join(__dir__, "pcs1", "**", "*.rb")).sort.each { |f| require f }

module Pcs1
  class Error < StandardError; end

  def self.configure
    @config ||= Config.new
    yield @config if block_given?
    @config
  end

  def self.config
    @config || configure
  end

  def self.site
    @site ||= resolve_site
  end

  def self.reset!
    @site = nil
    @config = nil
  end

  private

  def self.resolve_site
    host = Host.local
    host&.site
  end
end
