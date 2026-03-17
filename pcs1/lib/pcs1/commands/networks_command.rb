# frozen_string_literal: true

require "tty-prompt"

module Pcs1
  class NetworksCommand < RestCli::Command
    class List < self
      desc "List networks"

      def call(**options)
        networks = Pcs1::Network.all.to_a

        if networks.empty?
          puts "No networks. Run 'pcs1 network add' to create one."
          return
        end

        view.list(networks, **view_options(options))
      end
    end

    class Show < self
      desc "Show network details"

      argument :id, required: true, desc: "Network ID or name"

      def call(id:, **options)
        network = find_network(id)
        view.show(network, **view_options(options))
      end
    end

    class Scan < self
      desc "Scan a network for hosts"

      argument :name, required: false, desc: "Network name (default: primary)"

      def call(name: nil, **options)
        network = if name
                    find_network(name)
                  else
                    Pcs1::Network.find_by(primary: true)
                  end

        unless network
          $stderr.puts "Error: No primary network found. Run 'pcs1 network add' first."
          exit 1
        end

        puts "Scanning #{network.name} (#{network.subnet})..."

        counts = network.scan

        Pcs1::Host.reload!
        Pcs1::Interface.reload!

        puts "  New: #{counts[:new]}, Updated: #{counts[:updated]}, Unchanged: #{counts[:unchanged]}"
        puts

        hosts = Pcs1::Host.all.to_a
        if hosts.any?
          Pcs1::HostsView.new.list(hosts, **view_options(options))
        else
          puts "No hosts found."
        end
      end
    end

    class Add < self
      desc "Add a network"

      def call(**options)
        prompt = TTY::Prompt.new
        site = Pcs1::Site.first

        unless site
          $stderr.puts "Error: No site configured. Run 'pcs1 site add' first."
          exit 1
        end

        net = Pcs1::Network.new(site_id: site.id)

        net.name          = prompt_field(prompt, net, :name)
        net.subnet        = prompt_field(prompt, net, :subnet)
        net.gateway       = prompt_field(prompt, net, :gateway)
        dns_input         = prompt_field(prompt, net, :dns_resolvers,
                              label: "DNS resolvers (comma-separated)",
                              default: net.gateway)
        net.dns_resolvers = dns_input&.split(",")&.map(&:strip)
        net.primary       = Pcs1::Network.all.none?

        network = Pcs1::Network.create(
          name: net.name,
          subnet: net.subnet,
          gateway: net.gateway,
          dns_resolvers: net.dns_resolvers,
          primary: net.primary,
          site_id: site.id
        )

        view.show(network, **view_options(options))
      end
    end

    class Update < self
      desc "Update a network"

      argument :id, required: true, desc: "Network ID or name"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id:, field: nil, value: nil, **options)
        network = find_network(id)

        if field && value
          resolved = field == "dns_resolvers" ? value.split(",").map(&:strip) : value
          network.update(field.to_sym => resolved)
          puts "Network #{id}: #{field} = #{value}"
        else
          prompt = TTY::Prompt.new

          network.name          = prompt_field(prompt, network, :name)
          network.subnet        = prompt_field(prompt, network, :subnet)
          network.gateway       = prompt_field(prompt, network, :gateway)
          dns_input             = prompt_field(prompt, network, :dns_resolvers,
                                    label: "DNS resolvers (comma-separated)",
                                    default: network.dns_resolvers&.join(", "))
          network.dns_resolvers = dns_input&.split(",")&.map(&:strip)
          network.save!

          view.show(network, **view_options(options))
        end
      end
    end

    class Remove < self
      desc "Remove a network"

      argument :id, required: true, desc: "Network ID or name"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"

      def call(id:, force: false, **)
        network = find_network(id)

        unless force
          prompt = TTY::Prompt.new
          unless prompt.yes?("Remove network '#{network.name}'?", default: false)
            puts "Aborted."
            return
          end
        end

        network.interfaces.each(&:destroy)
        network.destroy
        puts "Network '#{network.name}' removed."
      end
    end

    private

    def find_network(id)
      Pcs1::Network.find(id.to_s)
    rescue FlatRecord::RecordNotFound
      network = Pcs1::Network.find_by(name: id.to_s)
      unless network
        $stderr.puts "Error: Network '#{id}' not found."
        exit 1
      end
      network
    end
  end
end
