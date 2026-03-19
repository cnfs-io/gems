# frozen_string_literal: true

require "tty-prompt"

module Pcs1
  class InterfacesCommand < RestCli::Command
    class List < self
      desc "List interfaces"

      def call(**options)
        interfaces = Pcs1::Interface.all.to_a

        if interfaces.empty?
          puts "No interfaces."
          return
        end

        view.list(interfaces, **view_options(options))
      end
    end

    class Show < self
      desc "Show interface details"

      argument :id, required: true, desc: "Interface ID"

      def call(id:, **options)
        iface = Pcs1::Interface.find(id.to_s)
        view.show(iface, **view_options(options))
      rescue FlatRecord::RecordNotFound
        warn "Error: Interface #{id} not found."
        exit 1
      end
    end

    class Add < self
      desc "Add an interface"

      argument :host_id, required: true, desc: "Host ID"
      argument :network_id, required: true, desc: "Network ID"

      def call(host_id:, network_id:, **options)
        prompt = TTY::Prompt.new

        host = Pcs1::Host.find(host_id.to_s)
        network = Pcs1::Network.find(network_id.to_s)

        iface = Pcs1::Interface.new(host_id: host.id, network_id: network.id)

        iface.name          = prompt_field(prompt, iface, :name)
        iface.configured_ip = prompt_field(prompt, iface, :configured_ip)
        iface.mac           = prompt_field(prompt, iface, :mac)

        interface = Pcs1::Interface.create(
          name: iface.name,
          configured_ip: iface.configured_ip,
          mac: iface.mac,
          host_id: host.id,
          network_id: network.id
        )

        view.show(interface, **view_options(options))
      rescue FlatRecord::RecordNotFound => e
        warn "Error: #{e.message}"
        exit 1
      end
    end

    class Update < self
      desc "Update an interface"

      argument :id, required: true, desc: "Interface ID"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id:, field: nil, value: nil, **options)
        iface = Pcs1::Interface.find(id.to_s)

        if field && value
          iface.update(field.to_sym => value)
          puts "Interface #{id}: #{field} = #{value}"
        else
          prompt = TTY::Prompt.new

          iface.name          = prompt_field(prompt, iface, :name)
          iface.configured_ip = prompt_field(prompt, iface, :configured_ip)
          iface.mac           = prompt_field(prompt, iface, :mac)
          iface.save!

          view.show(iface, **view_options(options))
        end
      rescue FlatRecord::RecordNotFound
        warn "Error: Interface #{id} not found."
        exit 1
      end
    end

    class Remove < self
      desc "Remove an interface"

      argument :id, required: true, desc: "Interface ID"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"

      def call(id:, force: false, **)
        iface = Pcs1::Interface.find(id.to_s)

        unless force
          prompt = TTY::Prompt.new
          unless prompt.yes?("Remove interface '#{iface.name || iface.id}'?", default: false)
            puts "Aborted."
            return
          end
        end

        iface.destroy
        puts "Interface '#{id}' removed."
      rescue FlatRecord::RecordNotFound
        warn "Error: Interface #{id} not found."
        exit 1
      end
    end
  end
end
