# frozen_string_literal: true

require "dry/cli"

module Pim
  module Commands
    class Console < Dry::CLI::Command
      desc "Start an interactive console with project context loaded"

      def call(**)
        require "pry"
        Pim.console_mode!
        Pry.start(Pim)
      end
    end
  end
end
