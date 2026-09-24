# frozen_string_literal: true

require "flat_record"
require_relative "pcs/version"
require_relative "pcs/config"
require_relative "pcs/boot"
require_relative "pcs/cli"

module Pcs
  class CommandError < StandardError; end

  BOOT_SKIP_COMMANDS = %w[new version completions].freeze

  def self.run(*args)
    flat_args = args.flat_map { |a| a.split(" ") }

    unless BOOT_SKIP_COMMANDS.include?(flat_args.first)
      boot!
    end

    Dry::CLI.new(Pcs::CLI).call(arguments: flat_args)
  rescue ProjectNotFoundError, CommandError => e
    $stderr.puts e.message
    exit 1
  end
end
