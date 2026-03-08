# frozen_string_literal: true

require "dry/cli"

module Pcs
  module Commands
    class Console < Dry::CLI::Command
      desc "Start a Pry console with PCS loaded"

      def call(*)
        # boot! is called by Pcs.run before this command
        require "pry"
        Pry.start(Pcs)
      end
    end
  end
end
