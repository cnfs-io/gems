# frozen_string_literal: true

require "dry/cli"

module Pim
  module Commands
    class New < Dry::CLI::Command
      desc "Create a new PIM project"

      argument :name, required: false, desc: "Project name (creates subdirectory)"

      def call(name: nil, **)
        target = name ? File.join(Dir.pwd, name) : Dir.pwd
        scaffold = Pim::New::Scaffold.new(target)
        scaffold.create
      end
    end
  end
end
