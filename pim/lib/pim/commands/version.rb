# frozen_string_literal: true

require "dry/cli"

module Pim
  module Commands
    class Version < Dry::CLI::Command
      desc "Print PIM version"

      def call(*)
        puts "pim #{Pim::VERSION}"
      end
    end
  end
end
