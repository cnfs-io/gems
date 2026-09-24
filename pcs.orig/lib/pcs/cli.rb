# frozen_string_literal: true

require "dry/cli"

# Models
require_relative "models/role"
require_relative "models/state"
require_relative "models/host"
require_relative "models/hosts/pve_host"
require_relative "models/hosts/truenas_host"
require_relative "models/hosts/pikvm_host"
require_relative "models/hosts/rpi_host"
require_relative "models/site"
require_relative "models/network"
require_relative "models/interface"
require_relative "models/profile"

# Network detection
require_relative "network_detect"

# Adapters
require_relative "adapters/system_cmd"
require_relative "adapters/dnsmasq"
require_relative "adapters/ssh"
require_relative "adapters/nmap"

# Providers
require_relative "providers/proxmox/installer"

# Services
require_relative "service"
require_relative "service/control_plane"
require_relative "service/dnsmasq"
require_relative "service/netboot"

# Views
require_relative "views"

# Resource commands
require_relative "commands/hosts_command"
require_relative "commands/networks_command"
require_relative "commands/services_command"
require_relative "commands/sites_command"
require_relative "commands/clusters_command"
require_relative "commands/cp_command"

# Standalone commands
require_relative "commands/new"
require_relative "commands/console"

module Pcs
  module CLI
    extend RestCli::Registry

    commands(project: Pcs.root, bin: "pcs",
             group_descriptions: { "cp" => "Control plane management" }) do
      register "version", Class.new(Dry::CLI::Command) {
        desc "Print PCS version"
        def call(*) = puts "pcs #{Pcs::VERSION}"
      }

      outside_project do
        register "new", Commands::New
      end

      inside_project do
        register "console",          Commands::Console, aliases: ["c"]

        # Hosts
        register "host list",        HostsCommand::List, aliases: ["ls"]
        register "host show",        HostsCommand::Show
        register "host add",         HostsCommand::Add, aliases: ["a"]
        register "host update",      HostsCommand::Update
        register "host remove",      HostsCommand::Remove, aliases: ["rm"]

        # Networks
        register "network list",     NetworksCommand::List, aliases: ["ls"]
        register "network show",     NetworksCommand::Show
        register "network add",      NetworksCommand::Add, aliases: ["a"]
        register "network update",   NetworksCommand::Update
        register "network remove",   NetworksCommand::Remove, aliases: ["rm"]

        # Sites
        register "site list",        SitesCommand::List, aliases: ["ls"]
        register "site show",        SitesCommand::Show
        register "site add",         SitesCommand::Add, aliases: ["a"]
        register "site remove",      SitesCommand::Remove, aliases: ["rm"]
        register "site use",         SitesCommand::Use
        register "site update",      SitesCommand::Update
      end

      platform(:linux) do
        register "network scan",     NetworksCommand::Scan

        # Services
        register "service list",     ServicesCommand::List, aliases: ["ls"]
        register "service show",     ServicesCommand::Show
        register "service start",    ServicesCommand::Start
        register "service stop",     ServicesCommand::Stop
        register "service restart",  ServicesCommand::Restart
        register "service reload",   ServicesCommand::Reload
        register "service status",   ServicesCommand::Status

        # Cluster
        register "cluster install",  ClustersCommand::Install

        # Control plane
        register "cp setup",         CpCommand::Setup
      end
    end
  end
end
