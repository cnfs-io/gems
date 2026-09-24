# frozen_string_literal: true

module Pcs
  module Commands
    # `pcs service status|start|stop|restart [NAME]`: the site's containers,
    # run by pcm from the definitions the pcs ppm package installs.
    module Service
      # Shared: which services, and the pcm adapter.
      class Base < Termino::Command
        argument :name, desc: "dnsmasq or netboot (default: both)"

        private

        def services(name)
          all = { "dnsmasq" => Pcs.settings.dnsmasq.service, "netboot" => Pcs.settings.netboot.service }
          return all.values unless name

          [all.fetch(name) do
            all.values.include?(name) ? name : abort("Error: no service #{name} (#{all.keys.join(", ")})")
          end]
        end

        def pcm
          @pcm ||= Adapters::Pcm.new
        end

        def each_service(name)
          enter_project!
          services(name).each do |service|
            next warn("#{service}: not installed (install the pcs ppm package)") unless pcm.installed?(service)

            yield service
          end
        end
      end

      # Whether each service is installed and running, and where pcs writes for it.
      class Status < Base
        desc "Show whether the services are running, and their recent logs"
        option :lines, type: :integer, default: 10, desc: "Log lines to show"

        def call(name: nil, lines: 10, **)
          each_service(name) do |service|
            running = pcm.running?(service)
            puts "#{service}: #{running ? "running" : "stopped"}"
            puts pcm.logs(service, lines:).lines.map { |l| "  #{l}" }.join if running && lines.to_i.positive?
          end
          show_paths
        end

        private

        # Where pcs writes the services' files (what their containers mount).
        def show_paths
          settings = Pcs.settings
          puts "config: #{settings.dnsmasq.config_dir}", "menus:  #{settings.netboot.menus_dir}",
               "assets: #{settings.netboot.assets_dir}"
        end
      end

      # pcm up.
      class Start < Base
        desc "Start the services"

        def call(name: nil, **)
          each_service(name) { |service| pcm.up(service) && puts("#{service}: started") }
        end
      end

      # pcm down.
      class Stop < Base
        desc "Stop the services"

        def call(name: nil, **)
          each_service(name) { |service| pcm.down(service) && puts("#{service}: stopped") }
        end
      end

      # Restart through pcm's compose passthrough.
      class Restart < Base
        desc "Restart the services"

        def call(name: nil, **)
          each_service(name) { |service| pcm.restart(service) && puts("#{service}: restarted") }
        end
      end
    end
  end
end
