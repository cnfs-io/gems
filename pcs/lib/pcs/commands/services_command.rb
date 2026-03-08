# frozen_string_literal: true

require "pastel"

module Pcs
  class ServicesCommand < RestCli::Command
    private

    def resolve_service(name)
      Pcs::Service.resolve(name)
    end

    def with_service_context(name)
      svc = resolve_service(name)
      site = Pcs::Site.load
      system_cmd = Adapters::SystemCmd.new
      [svc, site, system_cmd]
    rescue ArgumentError => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    rescue Pcs::ProjectNotFoundError, Pcs::SiteNotSetError => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    end

    class List < self
      desc "List all services"

      def call(**)
        system_cmd = Adapters::SystemCmd.new

        Pcs::Service.managed.each do |name, klass|
          status = klass.status(system_cmd: system_cmd)
          puts "#{name}: #{status}"
        end
      end
    end

    class Show < self
      desc "Show service information"

      argument :name, required: true, desc: "Service name"

      def call(name:, **)
        svc, _, system_cmd = with_service_context(name)
        puts "status: #{svc.status(system_cmd: system_cmd)}"
      end
    end

    class Start < self
      desc "Start a service"

      argument :name, required: true, desc: "Service name"

      def call(name:, **)
        svc, site, system_cmd = with_service_context(name)
        puts "Starting #{name}..."
        svc.start(site: site, system_cmd: system_cmd)
      end
    end

    class Stop < self
      desc "Stop a service"

      argument :name, required: true, desc: "Service name"

      def call(name:, **)
        svc, _, system_cmd = with_service_context(name)
        puts "Stopping #{name}..."
        svc.stop(system_cmd: system_cmd)
      end
    end

    class Restart < self
      desc "Restart a service (stop, regenerate config, start)"

      argument :name, required: true, desc: "Service name"

      def call(name:, **)
        svc, site, system_cmd = with_service_context(name)
        puts "Restarting #{name}..."
        svc.stop(system_cmd: system_cmd)
        svc.start(site: site, system_cmd: system_cmd)
      end
    end

    class Reload < self
      desc "Reload service config (regenerate without full restart where possible)"

      argument :name, required: true, desc: "Service name"

      def call(name:, **)
        svc, site, system_cmd = with_service_context(name)
        puts "Reloading #{name}..."
        svc.reload(site: site, system_cmd: system_cmd)
      end
    end

    class Status < self
      desc "Show service health, diagnostics, and recent logs"

      argument :name, required: true, desc: "Service name"
      option :follow, type: :boolean, default: false, aliases: ["-f"],
             desc: "Follow log output (tail -f)"
      option :lines, default: "50", aliases: ["-n"],
             desc: "Number of log lines to show"

      def call(name:, follow: false, lines: "50", **)
        svc, _, system_cmd = with_service_context(name)

        if follow
          exec(svc.log_command)
        else
          svc.status_report(system_cmd: system_cmd, pastel: Pastel.new, lines: lines.to_i)
        end
      end
    end
  end
end
