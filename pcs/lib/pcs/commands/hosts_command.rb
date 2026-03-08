# frozen_string_literal: true

require "ostruct"
require "tty-table"
require "tty-prompt"

module Pcs
  class HostsCommand < RestCli::Command
    class List < self
      desc "List hosts for the current site"

      def call(**options)
        hosts = Pcs::Host.load.to_a

        if hosts.empty?
          puts "No hosts. Run 'pcs network scan' to discover hosts."
          return
        end

        view.list(hosts, **view_options(options))
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Show < self
      desc "Show host details"

      argument :id, required: true, desc: "Host ID"

      def call(id:, **options)
        host = Pcs::Host.find(id.to_s)
        view.show(host, **view_options(options))
      rescue FlatRecord::RecordNotFound
        $stderr.puts "Error: Host #{id} not found."
        exit 1
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Add < self
      desc "Add a host to the current site"

      def call(**options)
        prompt = TTY::Prompt.new

        hostname = prompt_field(prompt, OpenStruct.new, :hostname)
        role     = prompt_field(prompt, OpenStruct.new, :role)
        type     = prompt_field(prompt, OpenStruct.new(role: role), :type)
        arch     = prompt_field(prompt, OpenStruct.new, :arch)

        host = Pcs::Host.create(
          hostname: hostname,
          role: role,
          type: type,
          arch: arch,
          site_id: Pcs.site,
          status: "configured",
          discovered_at: Time.now.iso8601,
          last_seen_at: Time.now.iso8601
        )

        view.show(host, **view_options(options))
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Remove < self
      desc "Remove a host from the current site"

      argument :id, required: true, desc: "Host ID"
      option :force, type: :boolean, default: false, desc: "Skip confirmation"

      def call(id:, force: false, **)
        host = Pcs::Host.find(id.to_s)

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
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end

    class Update < self
      desc "Update a host's settings"

      argument :id, required: false, desc: "Host ID"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id: nil, field: nil, value: nil, **)
        if field && value && id
          direct_set(id, field, value)
        else
          interactive_configure(id)
        end
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError,
             RuntimeError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end

      private

      def direct_set(id, field, value)
        host = Pcs::Host.find(id.to_s)
        host.update(field.to_sym => value)
        puts "Host #{id}: #{field} = #{value}"
      end

      def interactive_configure(id)
        prompt = TTY::Prompt.new

        host = resolve_host(prompt, id)

        host.role     = prompt_field(prompt, host, :role)
        host.type     = prompt_field(prompt, host, :type)
        compute_ip    = prompt_field(prompt, host, :compute_ip,
                          default: host.ip_on(:compute) || host.discovered_ip)
        host.hostname = prompt_field(prompt, host, :hostname)
        host.arch     = prompt_field(prompt, host, :arch, default: host.arch || "amd64")

        host.update(
          compute_ip: compute_ip,
          status: "configured"
        )

        puts "Host #{host.id} configured:"
        puts "  role:          #{host.role}"
        puts "  type:          #{host.type}"
        puts "  compute_ip:    #{compute_ip}"
        puts "  hostname:      #{host.hostname}"
        puts "  arch:          #{host.arch}"
        puts "  status:        configured"
      end

      def resolve_host(prompt, id)
        if id
          Pcs::Host.find(id.to_s)
        else
          hosts = Pcs::Host.load.to_a
          raise "No hosts. Run 'pcs network scan' to discover hosts." if hosts.empty?
          choices = hosts.map { |h| { name: "#{h.id}: #{h.discovered_ip} (#{h.mac || "no MAC"})", value: h } }
          prompt.select("Select host:", choices)
        end
      rescue FlatRecord::RecordNotFound
        raise "Host #{id} not found"
      end
    end
  end
end
