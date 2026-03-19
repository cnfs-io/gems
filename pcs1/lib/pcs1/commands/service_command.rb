# frozen_string_literal: true

module Pcs1
  class ServiceCommand < RestCli::Command
    SERVICES = {
      "dnsmasq" => Pcs1::Dnsmasq,
      "netboot" => Pcs1::Netboot
    }.freeze

    class Start < self
      desc "Start a service"

      argument :name, required: true, desc: "Service name (dnsmasq, netboot)"

      def call(name:, **)
        svc = resolve_service(name)
        svc.start!
      end
    end

    class Stop < self
      desc "Stop a service"

      argument :name, required: true, desc: "Service name (dnsmasq, netboot)"

      def call(name:, **)
        svc = resolve_service(name)
        svc.stop!
      end
    end

    class Status < self
      desc "Show service status"

      argument :name, required: false, desc: "Service name (omit for all)"

      def call(name: nil, **)
        if name
          svc = resolve_service(name)
          puts "#{name}: #{svc.status}"
        else
          SERVICES.each do |svc_name, svc_class|
            puts "#{svc_name}: #{svc_class.status}"
          end
        end
      end
    end

    class Restart < self
      desc "Restart a service"

      argument :name, required: true, desc: "Service name (dnsmasq, netboot)"

      def call(name:, **)
        svc = resolve_service(name)
        if svc.respond_to?(:restart!)
          svc.restart!
        else
          svc.stop!
          svc.start!
        end
      end
    end

    private

    def resolve_service(name)
      svc = SERVICES[name]
      unless svc
        warn "Unknown service '#{name}'. Available: #{SERVICES.keys.join(", ")}"
        exit 1
      end
      svc
    end
  end
end
