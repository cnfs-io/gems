# frozen_string_literal: true

require "ostruct"
require "tty-prompt"
require_relative "../platform"

module Pcs
  class SitesCommand < RestCli::Command
    class List < self
      desc "List sites"

      def call(**options)
        root = Pcs.project_dir
        sites_dir = root / "sites"

        unless sites_dir.exist?
          puts "No sites directory found."
          return
        end

        sites = sites_dir.children.select(&:directory?).map { |d| d.basename.to_s }.sort

        if sites.empty?
          puts "No sites found. Run 'pcs site add <name>' to create one."
          return
        end

        active = begin
          Pcs.site
        rescue Pcs::SiteNotSetError
          nil
        end

        rows = sites.map do |name|
          site = Pcs::Site.load(name)
          OpenStruct.new(
            name: name == active ? "* #{name}" : name,
            domain: site&.domain || "-"
          )
        end

        view.list(rows, **view_options(options))
      rescue Pcs::ProjectNotFoundError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Show < self
      desc "Show site details"

      argument :name, required: true, desc: "Site name"

      def call(name:, **options)
        site_dir = Pcs.project_dir / "sites" / name
        unless site_dir.exist?
          $stderr.puts "Error: Site '#{name}' not found."
          exit 1
        end

        site = Pcs::Site.load(name)
        view.show(site, **view_options(options))
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Add < self
      desc "Add a site"

      argument :name, required: true, desc: "Site name (e.g., roc, sg)"
      option :yes, type: :boolean, default: false, aliases: ["-y"], desc: "Accept all defaults"

      def call(name:, yes: false, **)
        @auto = yes

        unless name.match?(/\A[a-z][a-z0-9-]*\z/)
          $stderr.puts "Error: Site name must be lowercase alphanumeric + hyphens."
          exit 1
        end

        root = Pcs.project_dir
        site_dir = root / "sites" / name

        if site_dir.exist?
          $stderr.puts "Error: Site '#{name}' already exists."
          exit 1
        end

        prompt = @auto ? nil : TTY::Prompt.new
        system_cmd = Adapters::SystemCmd.new
        platform = Pcs::Platform.current

        net = platform.detect_network(system_cmd)
        fallback = Pcs.config.networking.dns_fallback_resolvers

        defaults = OpenStruct.new(
          domain: "#{name}.#{Pcs::Site.top_level_domain}",
          timezone: platform.detect_timezone(system_cmd),
          ssh_key: "~/.ssh/authorized_keys"
        )

        if @auto
          domain   = defaults.domain
          timezone = defaults.timezone
          ssh_key  = defaults.ssh_key
        else
          defaults.domain   = domain   = prompt_field(prompt, defaults, :domain)
          defaults.timezone = timezone = prompt_field(prompt, defaults, :timezone)
          defaults.ssh_key  = ssh_key  = prompt_field(prompt, defaults, :ssh_key)
        end
        hostname = @auto ? "ops1" : prompt.ask("Hostname:", default: "ops1")

        site_dir.mkpath

        site = Pcs::Site.new(name: name, domain: domain, timezone: timezone, ssh_key: ssh_key)
        site.save!

        Pcs::Site.reload!
        Pcs::Network.reload!
        Pcs::Host.reload!
        Pcs::Interface.reload!

        # Dynamic network loop
        network_index = 0
        last_subnet = net[:compute_subnet]

        loop do
          if network_index == 0
            default_name = "compute"
            default_subnet = last_subnet
          else
            default_name = prompt_next_network_name(network_index)
            default_subnet = increment_subnet_octet(last_subnet)
          end

          if @auto
            break if network_index > 0
            net_name = default_name
            subnet = default_subnet
            gateway = gateway_for(subnet)
            dns = [gateway] + fallback
          else
            net_name = prompt.ask("Network name:", default: default_name)
            subnet = prompt.ask("#{net_name} subnet:", default: default_subnet)
            gateway = prompt.ask("#{net_name} gateway:", default: gateway_for(subnet))
            dns = prompt.ask("#{net_name} DNS resolvers (comma-separated):",
                             default: ([gateway] + fallback).join(", "))
                         .split(",").map(&:strip)
          end

          Pcs::Network.create(
            name: net_name, subnet: subnet, gateway: gateway,
            dns_resolvers: dns, primary: network_index == 0, site_id: name
          )

          last_subnet = subnet
          network_index += 1

          break if @auto
          break unless prompt.yes?("Add another network?", default: false)
        end

        # Create CP host with interface on primary network
        primary_net = Pcs::Network.primary(name)
        host = Pcs::Host.create(
          discovered_ip: net[:current_ip],
          site_id: name,
          status: "discovered",
          connect_as: "root",
          hostname: hostname,
          discovered_at: Time.now.iso8601,
          last_seen_at: Time.now.iso8601
        )
        Pcs::Interface.create(
          mac: net[:mac], ip: net[:current_ip],
          host_id: host.id, network_id: primary_net.id, site_id: name
        )

        active = begin
          Pcs.site
        rescue Pcs::SiteNotSetError
          nil
        end

        unless active
          env_path = root / ".env"
          env_path.write("PCS_SITE=#{name}\n")
        end
      rescue Pcs::ProjectNotFoundError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      private

      def gateway_for(subnet)
        base = subnet.split("/").first
        octets = base.split(".")
        octets[3] = "1"
        octets.join(".")
      end

      def increment_subnet_octet(subnet)
        parts = subnet.split("/")
        octets = parts[0].split(".")
        octets[2] = (octets[2].to_i + 1).to_s
        "#{octets.join(".")}/#{parts[1]}"
      end

      def prompt_next_network_name(index)
        %w[compute storage management][index] || "network#{index}"
      end
    end

    class Remove < self
      desc "Remove a site"

      argument :name, required: true, desc: "Site name to remove"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"

      def call(name:, force: false, **)
        root = Pcs.project_dir
        site_dir = root / "sites" / name
        state_dir = root / "states" / name

        unless site_dir.exist?
          $stderr.puts "Error: Site '#{name}' not found."
          exit 1
        end

        unless force
          prompt = TTY::Prompt.new
          unless prompt.yes?("Remove site '#{name}' and all its data?", default: false)
            puts "Aborted."
            return
          end
        end

        site_dir.rmtree
        state_dir.rmtree if state_dir.exist?

        active = begin
          Pcs.site
        rescue Pcs::SiteNotSetError
          nil
        end

        puts "Removed site '#{name}'"
        puts "  Warning: '#{name}' was the active site." if active == name
      rescue Pcs::ProjectNotFoundError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Use < self
      desc "Set the active site"

      argument :name, required: true, desc: "Site name (e.g., roc, sg)"

      def call(name:, **)
        unless name.match?(/\A[a-z][a-z0-9-]*\z/)
          $stderr.puts "Error: Site name must be lowercase alphanumeric + hyphens."
          exit 1
        end

        root = Pcs.project_dir
        site_dir = root / "sites" / name

        unless site_dir.exist?
          $stderr.puts "Error: Site '#{name}' not found. Run 'pcs site add #{name}' first."
          exit 1
        end

        env_path = root / ".env"
        env_path.write("PCS_SITE=#{name}\n")
      rescue Pcs::ProjectNotFoundError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Update < self
      desc "Update a site's settings"

      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(field: nil, value: nil, **options)
        site = Pcs::Site.load

        if field && value
          direct_set(site, field, value)
        else
          interactive_configure(site, **options)
        end
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError,
             RuntimeError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      private

      def direct_set(site, field, value)
        site.send(:"#{field}=", value)
        site.save!
        puts "Site #{site.name}: #{field} = #{value}"
      end

      def interactive_configure(site, **options)
        prompt = TTY::Prompt.new

        site.domain   = prompt_field(prompt, site, :domain)
        site.timezone = prompt_field(prompt, site, :timezone)
        site.ssh_key  = prompt_field(prompt, site, :ssh_key)

        site.save!

        puts
        puts "Site updated:"
        view.show(site, **view_options(options))
      end
    end
  end
end
