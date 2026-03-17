# frozen_string_literal: true

require "dry/cli"

module Pcs1
  module Commands
    class Console < Dry::CLI::Command
      desc "Start a Pry console with PCS loaded"

      def call(*)
        require "pry"
        Pry.start(Pcs1)
      end
    end
  end
end
