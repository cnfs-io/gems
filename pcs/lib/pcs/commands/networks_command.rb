# frozen_string_literal: true

require "ostruct"
require "tty-prompt"

module Pcs
  class NetworksCommand < RestCli::Command
    class List < self
      desc "List networks for the current site"

      def call(**options)
        networks = Pcs::Network.load.to_a

        if networks.empty?
          puts "No networks. Run 'pcs site add' to create a site with networks."
          return
        end

        view.list(networks, **view_options(options))
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Show < self
      desc "Show network details"

      argument :name, required: true, desc: "Network name"

      def call(name:, **options)
        network = Pcs::Network.find_by_name(name)
        unless network
          $stderr.puts "Error: Network '#{name}' not found."
          exit 1
        end

        view.show(network, **view_options(options))
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Scan < self
      desc "Scan a network for hosts"

      argument :name, required: false, desc: "Network name (default: primary)"

      def call(name: nil, **)
        site_name = Pcs.site

        network = if name
                    Pcs::Network.find_by_name(name, site_name: site_name)
                  else
                    Pcs::Network.primary(site_name)
                  end

        unless network
          target = name || "primary"
          $stderr.puts "Error: Network '#{target}' not found."
          exit 1
        end

        cp_host = Pcs::Host.load(site_name).detect { |h| h.role == "cp" }
        unless cp_host
          $stderr.puts "Error: No control plane host found."
          exit 1
        end

        cp_iface = cp_host.interface_on(network.name)
        unless cp_iface
          $stderr.puts "Error: Control plane host has no interface on '#{network.name}' network."
          $stderr.puts "  Configure an interface first with 'pcs host set #{cp_host.id}'."
          exit 1
        end

        unless network.contains_ip?(cp_iface.ip)
          $stderr.puts "Error: CP interface IP #{cp_iface.ip} is not in #{network.name} subnet #{network.subnet}."
          exit 1
        end

        puts "Scanning #{network.name} (#{network.subnet})..."

        nmap = Adapters::Nmap.new
        results = nmap.scan(network.subnet)

        counts = Pcs::Host.merge_scan(site_name, results, network: network)

        puts "  New: #{counts[:new]}, Updated: #{counts[:updated]}, Unchanged: #{counts[:unchanged]}"
        puts

        hosts = Pcs::Host.load(site_name)
        if hosts.none?
          puts "No hosts found."
          return
        end

        Pcs::HostsView.new.list(hosts.to_a)
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError,
             RuntimeError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Add < self
      desc "Add a network to the current site"

      argument :name, required: true, desc: "Network name (e.g., storage, management)"

      def call(name:, **options)
        site_name = Pcs.site

        if Pcs::Network.find_by_name(name, site_name: site_name)
          $stderr.puts "Error: Network '#{name}' already exists."
          exit 1
        end

        prompt = TTY::Prompt.new
        net = OpenStruct.new(name: name, subnet: nil, gateway: nil, dns_resolvers: nil)

        net.subnet      = prompt_field(prompt, net, :subnet)
        net.gateway     = prompt_field(prompt, net, :gateway)
        dns_input       = prompt_field(prompt, net, :dns_resolvers, label: "DNS resolvers (comma-separated)")
        net.dns_resolvers = dns_input&.split(",")&.map(&:strip)

        Pcs::Network.create(
          name: name, subnet: net.subnet, gateway: net.gateway,
          dns_resolvers: net.dns_resolvers, primary: false, site_id: site_name
        )

        puts "Network '#{name}' added."
        network = Pcs::Network.find_by_name(name, site_name: site_name)
        view.show(network, **view_options(options))
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Update < self
      desc "Update a network's settings"

      argument :name, required: true, desc: "Network name"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(name:, field: nil, value: nil, **options)
        network = Pcs::Network.find_by_name(name)
        unless network
          $stderr.puts "Error: Network '#{name}' not found."
          exit 1
        end

        if field && value
          direct_set(network, name, field, value)
        else
          interactive_configure(network, **options)
        end
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      private

      def direct_set(network, name, field, value)
        resolved = field == "dns_resolvers" ? value.split(",").map(&:strip) : value
        network.send(:"#{field}=", resolved)
        network.save!
        puts "Network #{name}: #{field} = #{value}"
      end

      def interactive_configure(network, **options)
        prompt = TTY::Prompt.new

        network.subnet      = prompt_field(prompt, network, :subnet)
        network.gateway     = prompt_field(prompt, network, :gateway)
        dns_input           = prompt_field(prompt, network, :dns_resolvers,
                                label: "DNS resolvers (comma-separated)",
                                default: network.dns_resolvers&.join(", "))
        network.dns_resolvers = dns_input&.split(",")&.map(&:strip)

        network.save!

        puts
        puts "Network updated:"
        view.show(network, **view_options(options))
      end
    end

    class Remove < self
      desc "Remove a network from the current site"

      argument :name, required: true, desc: "Network name"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"

      def call(name:, force: false, **)
        network = Pcs::Network.find_by_name(name)
        unless network
          $stderr.puts "Error: Network '#{name}' not found."
          exit 1
        end

        if network.primary
          $stderr.puts "Error: Cannot remove the primary network '#{name}'."
          exit 1
        end

        unless force
          prompt = TTY::Prompt.new
          unless prompt.yes?("Remove network '#{name}'?", default: false)
            puts "Aborted."
            return
          end
        end

        network.destroy
        puts "Network '#{name}' removed."
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end
  end
end
