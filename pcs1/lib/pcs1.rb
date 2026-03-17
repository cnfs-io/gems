# frozen_string_literal: true

require "flat_record"
require "rest_cli"
require_relative "pcs1/version"
require_relative "pcs1/platform"
require_relative "pcs1/application"
require_relative "pcs1/cli"

module Pcs1
  class Error < StandardError; end

  def self.site
    @site ||= resolve_site
  end

  def self.reset!
    @site = nil
  end

  private

  def self.resolve_site
    host = Host.local
    host&.site
  end
end
