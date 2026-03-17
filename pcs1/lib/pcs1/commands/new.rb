# frozen_string_literal: true

require "tty-prompt"
require "pathname"
require "fileutils"

module Pcs1
  module Commands
    class New < RestCli::Command
      desc "Create a new PCS site project"

      argument :name, required: true, desc: "Site/project name (e.g., sg, roc)"

      EMPTY_YAML = "---\n[]\n"

      def call(name:, **)
        root = Pathname.pwd / name

        if root.exist?
          $stderr.puts "Error: Directory '#{name}' already exists."
          exit 1
        end

        prompt = TTY::Prompt.new

        # --- Scaffold ---
        puts "Creating project '#{name}'..."
        data_dir = root / "data"
        data_dir.mkpath
        %w[sites hosts networks interfaces].each do |file|
          (data_dir / "#{file}.yml").write(EMPTY_YAML)
        end

        # --- Boot FlatRecord against the new project ---
        FlatRecord.configure { |c| c.data_path = data_dir.to_s }
        Pcs1::Site.reload!
        Pcs1::Host.reload!
        Pcs1::Network.reload!
        Pcs1::Interface.reload!

        # --- Site ---
        site = create_site(prompt, name)

        # --- Host (this machine as CP) ---
        hostname = `hostname -s 2>/dev/null`.strip
        hostname = "ops1" if hostname.empty?
        host = Pcs1::Host.create(
          hostname: hostname,
          role: "cp",
          type: "rpi",
          arch: detect_arch,
          status: "configured",
          site_id: site.id
        )
        puts "  Host '#{hostname}' created (role: cp)"

        # --- Networks + Interfaces from local IPs ---
        ips = Pcs1::Host.local_ips
        if ips.empty?
          puts "  No local IPs detected. Add networks manually with 'pcs1 network add'."
        else
          network_index = 0
          ips.each do |ip|
            next unless prompt.yes?("Found IP #{ip} — add to a network?", default: true)

            network = create_network_for_ip(prompt, site, ip, network_index)
            create_interface(host, network, ip)
            network_index += 1
          end
        end

        puts
        puts "Project '#{name}' created."
        puts "  cd #{name} && pcs1 console"
      end

      private

      def prompt_for(tty_prompt, view_class, record, field_name, label: nil, default: nil)
        config = view_class.prompt_config_for(field_name)
        label ||= field_name.to_s.tr("_", " ").capitalize
        current = default || (record.respond_to?(field_name) ? record.send(field_name) : nil)

        unless config
          return tty_prompt.ask("#{label}:", default: current)
        end

        if config[:default]
          computed = config[:default].is_a?(Proc) ? config[:default].call(record) : config[:default]
          current = computed unless default
        end

        case config[:type]
        when :select
          choices = config[:choices].is_a?(Proc) ? config[:choices].call(record) : config[:choices]
          opts = {}
          opts[:filter] = true if config[:filter]
          idx = choices.index(current.to_s) if current
          opts[:default] = idx + 1 if idx
          tty_prompt.select("#{label}:", choices, **opts)
        else
          tty_prompt.ask("#{label}:", default: current)
        end
      end

      def create_site(prompt, default_name)
        site_record = Pcs1::Site.new(name: default_name)

        name     = prompt_for(prompt, Pcs1::SitesView, site_record, :name, default: default_name)
        domain   = prompt_for(prompt, Pcs1::SitesView, site_record, :domain, default: "#{name}.local")
        timezone = prompt_for(prompt, Pcs1::SitesView, site_record, :timezone, default: detect_timezone)
        ssh_key  = prompt_for(prompt, Pcs1::SitesView, site_record, :ssh_key)

        site = Pcs1::Site.create(
          name: name,
          domain: domain,
          timezone: timezone,
          ssh_key: ssh_key
        )
        puts "  Site '#{name}' created (#{domain})"
        site
      end

      def create_network_for_ip(prompt, site, ip, index)
        default_name = index == 0 ? "compute" : "network#{index}"
        default_subnet = subnet_from_ip(ip)
        default_gateway = gateway_from_ip(ip)

        net_record = Pcs1::Network.new(subnet: default_subnet)

        name    = prompt_for(prompt, Pcs1::NetworksView, net_record, :name, default: default_name)
        subnet  = prompt_for(prompt, Pcs1::NetworksView, net_record, :subnet, default: default_subnet)
        gateway = prompt_for(prompt, Pcs1::NetworksView, net_record, :gateway, default: default_gateway)
        dns_input = prompt_for(prompt, Pcs1::NetworksView, net_record, :dns_resolvers,
                      label: "DNS resolvers (comma-separated)",
                      default: "#{gateway}, 1.1.1.1")
        dns_resolvers = dns_input.split(",").map(&:strip)

        network = Pcs1::Network.create(
          name: name,
          subnet: subnet,
          gateway: gateway,
          dns_resolvers: dns_resolvers,
          primary: index == 0,
          site_id: site.id
        )
        puts "  Network '#{name}' created (#{subnet})"
        network
      end

      def create_interface(host, network, ip)
        iface = Pcs1::Interface.create(
          discovered_ip: ip,
          ip: ip,
          host_id: host.id,
          network_id: network.id
        )
        puts "  Interface created (#{ip} on #{network.name})"
        iface
      end

      def subnet_from_ip(ip)
        octets = ip.split(".")
        "#{octets[0]}.#{octets[1]}.#{octets[2]}.0/24"
      end

      def gateway_from_ip(ip)
        octets = ip.split(".")
        "#{octets[0]}.#{octets[1]}.#{octets[2]}.1"
      end

      def detect_timezone
        if File.exist?("/etc/localtime") && File.symlink?("/etc/localtime")
          File.readlink("/etc/localtime").sub(%r{.*/zoneinfo/}, "")
        else
          "UTC"
        end
      rescue StandardError
        "UTC"
      end

      def detect_arch
        case RUBY_PLATFORM
        when /aarch64|arm64/ then "arm64"
        when /x86_64|x64/ then "amd64"
        else "unknown"
        end
      end
    end
  end
end
