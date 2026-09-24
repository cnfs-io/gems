# frozen_string_literal: true

require "dry/cli"
require_relative "commands/new_site"
require_relative "commands/scan"
require_relative "commands/reconcile"
require_relative "commands/service"
require_relative "commands/host_operations"

module Pcs
  # The `pcs` command: termino's project commands plus pcs's own.
  module CLI
    extend Dry::CLI::Registry

    Termino::Commands.register(self, Pcs, new_project: Commands::NewSite) do |r|
      r.register "networks scan", Commands::Scan
      r.register "hosts key", Commands::HostOperations::Key
      r.register "hosts configure", Commands::HostOperations::Configure
      r.register "hosts install", Commands::HostOperations::Install
      r.register "reconcile", Commands::Reconcile
      r.register "service" do |service|
        service.register "status", Commands::Service::Status
        service.register "start", Commands::Service::Start
        service.register "stop", Commands::Service::Stop
        service.register "restart", Commands::Service::Restart
      end
    end
  end
end
