# frozen_string_literal: true

require "dry/cli"

# Resource commands
require_relative "commands/profiles_command"
require_relative "commands/isos_command"
require_relative "commands/builds_command"
require_relative "commands/targets_command"
require_relative "commands/ventoy_command"
require_relative "commands/vm_command"
require_relative "commands/image_command"
require_relative "commands/config_command"

# Standalone commands
require_relative "commands/version"
require_relative "commands/new"
require_relative "commands/console"
require_relative "commands/serve"

module Pim
  module CLI
    extend RestCli::Registry

    commands(project: Pim.root, bin: "pim") do
      register "version", Commands::Version

      outside_project do
        register "new", Commands::New
      end

      inside_project do
        register "console",          Commands::Console, aliases: ["c"]
        register "serve",            Commands::Serve, aliases: ["s"]

        # Profiles
        register "profile list",     ProfilesCommand::List, aliases: ["ls"]
        register "profile show",     ProfilesCommand::Show
        register "profile add",      ProfilesCommand::Add
        register "profile update",   ProfilesCommand::Update
        register "profile remove",   ProfilesCommand::Remove, aliases: ["rm"]

        # ISOs
        register "iso list",         IsosCommand::List, aliases: ["ls"]
        register "iso show",         IsosCommand::Show
        register "iso download",     IsosCommand::Download
        register "iso verify",       IsosCommand::Verify
        register "iso add",          IsosCommand::Add
        register "iso update",       IsosCommand::Update
        register "iso remove",       IsosCommand::Remove, aliases: ["rm"]

        # Builds
        register "build list",       BuildsCommand::List, aliases: ["ls"]
        register "build show",       BuildsCommand::Show
        register "build run",        BuildsCommand::Run
        register "build clean",      BuildsCommand::Clean
        register "build status",     BuildsCommand::Status
        register "build verify",     BuildsCommand::Verify
        register "build update",     BuildsCommand::Update

        # Targets
        register "target list",      TargetsCommand::List, aliases: ["ls"]
        register "target show",      TargetsCommand::Show
        register "target add",       TargetsCommand::Add
        register "target update",    TargetsCommand::Update
        register "target remove",    TargetsCommand::Remove, aliases: ["rm"]

        # Ventoy
        register "ventoy prepare",   VentoyCommand::Prepare
        register "ventoy copy",      VentoyCommand::Copy
        register "ventoy status",    VentoyCommand::Status
        register "ventoy show",      VentoyCommand::Show
        register "ventoy download",  VentoyCommand::Download

        # Images
        register "image list",       ImageCommand::List, aliases: ["ls"]
        register "image show",       ImageCommand::Show
        register "image delete",     ImageCommand::Delete, aliases: ["rm"]
        register "image publish",    ImageCommand::Publish
        register "image deploy",    ImageCommand::Deploy

        # VMs
        register "vm run",           VmCommand::Run
        register "vm list",          VmCommand::List, aliases: ["ls"]
        register "vm stop",          VmCommand::Stop
        register "vm ssh",           VmCommand::Ssh

        # Config
        register "config list",      ConfigCommand::List, aliases: ["ls"]
        register "config get",       ConfigCommand::Get
        register "config set",       ConfigCommand::Set
      end
    end
  end
end
