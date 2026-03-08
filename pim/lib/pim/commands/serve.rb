# frozen_string_literal: true

require "dry/cli"

module Pim
  module Commands
    class Serve < Dry::CLI::Command
      desc "Start preseed server for the given profile"

      argument :profile_name, required: false, desc: "Profile name (default: from config or 'default')"

      option :port, type: :integer, default: 8080, desc: "Port to serve on"
      option :preseed, type: :string, aliases: ["-p"], desc: "Preseed template name (default: profile name)"
      option :install, type: :string, aliases: ["-i"], desc: "Post-install script name (default: profile name)"
      option :verbose, type: :boolean, default: false, aliases: ["-v"], desc: "Verbose output"
      option :debug, type: :boolean, default: false, aliases: ["-d"], desc: "Show preseed and install file contents"

      def call(profile_name: nil, port: nil, preseed: nil, install: nil, verbose: false, debug: false, **)
        profile_name ||= Pim.config.serve_profile || 'default'
        port ||= Pim.config.serve_port
        profile = Pim::Profile.find(profile_name)

        preseed_name = preseed || profile_name

        unless profile.preseed_template(preseed)
          puts "Error: No preseed template found for '#{preseed_name}'"
          puts "Expected locations:"
          puts "  - ./resources/preseeds/#{preseed_name}.cfg.erb"
          Pim.exit!(1)
        end

        server = Pim::Server.new(
          profile: profile,
          port: port,
          verbose: verbose,
          debug: debug,
          preseed_name: preseed,
          install_name: install
        )

        server.start
      rescue FlatRecord::RecordNotFound
        puts "Error: Profile '#{profile_name}' not found"
        puts "Available profiles: #{Pim::Profile.all.map(&:id).join(', ')}"
        Pim.exit!(1)
      end
    end
  end
end
