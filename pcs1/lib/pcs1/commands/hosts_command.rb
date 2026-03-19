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
        warn "Error: Host #{id} not found."
        exit 1
      end
    end

    class Add < self
      desc "Add a host"

      def call(**options)
        prompt = TTY::Prompt.new
        site = Pcs1::Site.first

        unless site
          warn "Error: No site configured. Run 'pcs1 site add' first."
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
        warn "Error: Host #{id} not found."
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

            pxe = prompt.yes?("PXE boot this host?", default: false)
            host.pxe_boot = pxe

            host.status = "configured"
            host.save!

            # Configure each interface
            host.interfaces.each do |ifc|
              net = ifc.network
              net_name = net&.name || "unknown"
              puts
              puts "  Interface on #{net_name} (discovered: #{ifc.discovered_ip}, MAC: #{ifc.mac})"

              ifc.configured_ip = prompt_for(prompt, iface_view, ifc, :configured_ip,
                                             label: "  Static IP",
                                             default: ifc.discovered_ip)
              ifc.name = prompt_for(prompt, iface_view, ifc, :name,
                                    label: "  NIC name")
              ifc.save!
            end

            puts
            view.show(host, **view_options(options))
          else
            puts "  Skipped."
          end
          puts
        end

        remaining = Pcs1::Host.all.count { |h| h.status == "discovered" }
        if remaining.positive?
          puts "#{remaining} host(s) still discovered. Run 'pcs1 host configure' again."
        else
          puts "All hosts configured."
        end
      end

      private

      def prompt_for(tty_prompt, view_class, record, field_name, label: nil, default: nil)
        config = view_class.prompt_config_for(field_name)
        label ||= field_name.to_s.tr("_", " ").capitalize
        current = default || (record.respond_to?(field_name) ? record.send(field_name) : nil)

        return tty_prompt.ask("#{label}:", default: current) unless config

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

    class Provision < self
      desc "Provision a configured host (verify networking at configured IP)"

      argument :id, required: false, desc: "Host ID"

      def call(id: nil, **options)
        host = select_host(id, status: "configured")

        puts "Provisioning #{host.hostname} (#{host.type})..."
        puts

        host.provision!

        puts
        view.show(Host.find(host.id), **view_options(options))
      rescue StandardError => e
        warn "Error: #{e.message}"
        exit 1
      end

      private

      def select_host(id, status:)
        return Pcs1::Host.find(id.to_s) if id

        prompt = TTY::Prompt.new
        hosts = Pcs1::Host.all.select { |h| h.status == status }

        if hosts.empty?
          warn "No #{status} hosts to provision."
          exit 1
        end

        choices = hosts.map { |h| { name: "#{h.id}: #{h.hostname} (#{h.type})", value: h } }
        prompt.select("Select host to provision:", choices)
      end
    end

    class Install < self
      desc "Install OS on a PXE-bootable host"

      argument :id, required: false, desc: "Host ID"

      def call(id: nil, **options)
        host = select_host(id)

        unless host.pxe_target?
          warn "Error: Host #{host.hostname} is not a PXE target."
          warn "  pxe_boot: #{host.pxe_boot}, type: #{host.type}, local: #{host.local?}"
          exit 1
        end

        puts "Installing OS on #{host.hostname} (#{host.type})..."
        puts

        # Ensure services are running
        ensure_services_running

        # Generate PXE files
        Pcs1.site.reconcile!
        puts

        # Guide the operator
        iface = host.interfaces.first
        puts "PXE boot files generated for #{host.hostname}."
        puts
        puts "Next steps:"
        puts "  1. Set #{host.hostname} to boot from network (PXE/UEFI)"
        puts "  2. Reboot the host — it will PXE boot and install #{host.type} automatically"
        puts "  3. Wait for the install to complete and the host to reboot"
        puts
        puts "Waiting for #{host.hostname} to come online at #{iface&.configured_ip}..."
        puts "(Press Ctrl-C to cancel and verify manually later)"
        puts

        begin
          host.send(:wait_for_host, iface.configured_ip)

          if host.key_access?(target: :configured_ip)
            Pcs1.logger.info("Verified: #{host.hostname} reachable at #{iface.configured_ip}")
            host.fire_status_event(:provision)
            host.save!
            puts
            puts "#{host.hostname} installed and provisioned."
          else
            puts
            puts "Host came online but SSH key access failed."
            puts "Verify manually with: pcs1 console → host.key_access?(target: :configured_ip)"
          end
        rescue Interrupt
          puts
          puts "Cancelled. Run 'pcs1 host provision #{host.id}' to verify later."
        rescue StandardError => e
          puts
          puts "Host not yet online: #{e.message}"
          puts "The install may still be running. Check again with:"
          puts "  pcs1 host provision #{host.id}"
        end

        puts
        view.show(Host.find(host.id), **view_options(options))
      rescue FlatRecord::RecordNotFound
        warn "Error: Host #{id} not found."
        exit 1
      end

      private

      def select_host(id)
        return Pcs1::Host.find(id.to_s) if id

        prompt = TTY::Prompt.new
        hosts = Pcs1::Host.all.select(&:pxe_target?)

        if hosts.empty?
          warn "No PXE-bootable hosts found."
          warn "Configure hosts with pxe_boot: true using 'pcs1 host configure'."
          exit 1
        end

        choices = hosts.map { |h| { name: "#{h.id}: #{h.hostname} (#{h.type})", value: h } }
        prompt.select("Select host to install:", choices)
      end

      def ensure_services_running
        if Dnsmasq.status != "active"
          puts "Starting dnsmasq..."
          Dnsmasq.start!
        end

        if Netboot.status == "stopped"
          puts "Starting netboot..."
          Netboot.start!
        end
      end
    end

    class Upgrade < self
      desc "Upgrade a provisioned host to a new type (e.g., debian → proxmox)"

      argument :id, required: false, desc: "Host ID"
      argument :type, required: false, desc: "New host type (e.g., proxmox)"

      def call(id: nil, type: nil, **options)
        host = select_host(id)
        type = select_type(type, host)

        puts "Upgrading #{host.hostname} from #{host.type} to #{type}..."
        puts

        # Change the STI type
        host = host.becomes!(type)

        # Run type-specific upgrade if available
        if host.respond_to?(:install_pve!) && type == "proxmox"
          host.install_pve!
        end

        puts
        view.show(Host.find(host.id), **view_options(options))
      rescue ArgumentError => e
        warn "Error: #{e.message}"
        exit 1
      rescue FlatRecord::RecordNotFound
        warn "Error: Host #{id} not found."
        exit 1
      rescue StandardError => e
        warn "Error: #{e.message}"
        exit 1
      end

      private

      def select_host(id)
        return Pcs1::Host.find(id.to_s) if id

        prompt = TTY::Prompt.new
        hosts = Pcs1::Host.all.select { |h| h.status == "provisioned" }

        if hosts.empty?
          warn "No provisioned hosts to upgrade."
          exit 1
        end

        choices = hosts.map { |h| { name: "#{h.id}: #{h.hostname} (#{h.type})", value: h } }
        prompt.select("Select host to upgrade:", choices)
      end

      def select_type(type, host)
        return type if type && Host.valid_types.include?(type)

        prompt = TTY::Prompt.new
        available = Host.valid_types - [host.type]

        if available.empty?
          warn "No other host types available."
          exit 1
        end

        prompt.select("Upgrade to:", available)
      end
    end

    class Remove < self
      desc "Remove a host"

      argument :id, required: true, desc: "Host ID"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"

      def call(id:, force: false, **_options)
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
        warn "Error: Host #{id} not found."
        exit 1
      end
    end
  end
end
