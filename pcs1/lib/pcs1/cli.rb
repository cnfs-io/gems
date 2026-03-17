# frozen_string_literal: true

require "dry/cli"

# Models
require_relative "models/site"
require_relative "models/host"
require_relative "models/hosts/pikvm_host"
require_relative "models/network"
require_relative "models/interface"

# Views
require_relative "views/sites_view"
require_relative "views/hosts_view"
require_relative "views/networks_view"
require_relative "views/interfaces_view"

# Commands
require_relative "commands/console"
require_relative "commands/new"
require_relative "commands/sites_command"
require_relative "commands/hosts_command"
require_relative "commands/networks_command"
require_relative "commands/interfaces_command"

module Pcs1
  module CLI
    extend RestCli::Registry

    commands(project: nil, bin: "pcs1") do
      register "version", Class.new(Dry::CLI::Command) {
        desc "Print PCS version"
        def call(*) = puts "pcs1 #{Pcs1::VERSION}"
      }

      register "new",     Commands::New
      register "console", Commands::Console, aliases: ["c"]

      # Site (singleton)
      register "site add",       SitesCommand::Add
      register "site show",      SitesCommand::Show
      register "site update",    SitesCommand::Update

      # Hosts
      register "host list",      HostsCommand::List, aliases: ["ls"]
      register "host show",      HostsCommand::Show
      register "host add",       HostsCommand::Add
      register "host update",    HostsCommand::Update
      register "host configure", HostsCommand::Configure
      register "host remove",    HostsCommand::Remove, aliases: ["rm"]

      # Networks
      register "network list",   NetworksCommand::List, aliases: ["ls"]
      register "network show",   NetworksCommand::Show
      register "network scan",   NetworksCommand::Scan
      register "network add",    NetworksCommand::Add
      register "network update", NetworksCommand::Update
      register "network remove", NetworksCommand::Remove, aliases: ["rm"]

      # Interfaces
      register "interface list",   InterfacesCommand::List, aliases: ["ls"]
      register "interface show",   InterfacesCommand::Show
      register "interface add",    InterfacesCommand::Add
      register "interface update", InterfacesCommand::Update
      register "interface remove", InterfacesCommand::Remove, aliases: ["rm"]
    end
  end
end
