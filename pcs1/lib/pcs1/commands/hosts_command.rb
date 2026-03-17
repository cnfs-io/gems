# frozen_string_literal: true

require "tty-prompt"

module Pcs1
  class HostsCommand < RestCli::Command
    class List < self
      desc "List hosts"

      def call(**options)
        hosts = Pcs1::Host.all.to_a

        if hosts.empty?
          puts "No hosts. Run 'pcs1 network scan' to discover hosts."
          return
        end

        view.list(hosts, **view_options(options))
      end
    end

    class Show < self
      desc "Show host details"

      argument :id, required: true, desc: "Host ID"

      def call(id:, **options)
        host = Pcs1::Host.find(id.to_s)
        view.show(host, **view_options(options))
      rescue FlatRecord::RecordNotFound
        $stderr.puts "Error: Host #{id} not found."
        exit 1
      end
    end

    class Add < self
      desc "Add a host"

      def call(**options)
        prompt = TTY::Prompt.new
        site = Pcs1::Site.first

        unless site
          $stderr.puts "Error: No site configured. Run 'pcs1 site add' first."
          exit 1
        end

        hostname = prompt_field(prompt, Pcs1::Host.new, :hostname)
        role     = prompt_field(prompt, Pcs1::Host.new, :role)
        type     = prompt_field(prompt, Pcs1::Host.new, :type)
        arch     = prompt_field(prompt, Pcs1::Host.new, :arch)

        host = Pcs1::Host.create(
          hostname: hostname,
          role: role,
          type: type,
          arch: arch,
          status: "configured",
          site_id: site.id
        )

        view.show(host, **view_options(options))
      end
    end

    class Update < self
      desc "Update a host"

      argument :id, required: false, desc: "Host ID"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id: nil, field: nil, value: nil, **options)
        if id && field && value
          host = Pcs1::Host.find(id.to_s)
          host.update(field.to_sym => value)
          puts "Host #{id}: #{field} = #{value}"
        elsif id
          host = Pcs1::Host.find(id.to_s)
          interactive_update(host, **options)
        else
          prompt = TTY::Prompt.new
          hosts = Pcs1::Host.all.to_a
          raise "No hosts." if hosts.empty?

          choices = hosts.map { |h| { name: "#{h.id}: #{h.hostname || "(no hostname)"}", value: h } }
          host = prompt.select("Select host:", choices)
          interactive_update(host, **options)
        end
      rescue FlatRecord::RecordNotFound
        $stderr.puts "Error: Host #{id} not found."
        exit 1
      end

      private

      def interactive_update(host, **options)
        prompt = TTY::Prompt.new

        host.hostname = prompt_field(prompt, host, :hostname)
        host.role     = prompt_field(prompt, host, :role)
        host.type     = prompt_field(prompt, host, :type)
        host.arch     = prompt_field(prompt, host, :arch)
        host.save!

        view.show(host, **view_options(options))
      end
    end

    class Configure < self
      desc "Walk through unconfigured (discovered) hosts"

      def call(**options)
        discovered = Pcs1::Host.all.select { |h| h.status == "discovered" }

        if discovered.empty?
          puts "No discovered hosts to configure."
          return
        end

        prompt = TTY::Prompt.new
        iface_view = Pcs1::InterfacesView
        puts "Found #{discovered.size} discovered host(s)."
        puts

        discovered.each_with_index do |host, i|
          iface = host.interfaces.first
          disc_ip = iface&.discovered_ip || "unknown IP"
          mac = iface&.mac || "unknown MAC"

          puts "--- Host #{i + 1}/#{discovered.size} (#{disc_ip}, MAC: #{mac}) ---"

          if prompt.yes?("Configure this host?", default: true)
            host.hostname = prompt_field(prompt, host, :hostname)
            host.role     = prompt_field(prompt, host, :role)
            host.type     = prompt_field(prompt, host, :type)
            host.arch     = prompt_field(prompt, host, :arch)
            host.status   = "configured"
            host.save!

            # Configure each interface — assign static IP and NIC name
            host.interfaces.each do |ifc|
              net = ifc.network
              net_name = net&.name || "unknown"
              puts
              puts "  Interface on #{net_name} (discovered: #{ifc.discovered_ip}, MAC: #{ifc.mac})"

              ifc.ip   = prompt_for(prompt, iface_view, ifc, :ip,
                           label: "  Static IP",
                           default: ifc.discovered_ip)
              ifc.name = prompt_for(prompt, iface_view, ifc, :name,
                           label: "  NIC name")
              ifc.save!
            end

            puts
            view.show(host, **view_options(options))
            puts
          else
            puts "  Skipped."
            puts
          end
        end

        remaining = Pcs1::Host.all.count { |h| h.status == "discovered" }
        if remaining > 0
          puts "#{remaining} host(s) still discovered. Run 'pcs1 host configure' again to configure them."
        else
          puts "All hosts configured."
        end
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
    end

    class Remove < self
      desc "Remove a host"

      argument :id, required: true, desc: "Host ID"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"

      def call(id:, force: false, **options)
        host = Pcs1::Host.find(id.to_s)

        unless force
          prompt = TTY::Prompt.new
          unless prompt.yes?("Remove host '#{host.hostname || host.id}'?", default: false)
            puts "Aborted."
            return
          end
        end

        host.interfaces.each(&:destroy)
        host.destroy
        puts "Host '#{id}' removed."
      rescue FlatRecord::RecordNotFound
        $stderr.puts "Error: Host #{id} not found."
        exit 1
      end
    end
  end
end
