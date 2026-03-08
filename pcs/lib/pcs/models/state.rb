# frozen_string_literal: true

require "yaml"
require "pathname"
require "time"

module Pcs
  class State
      VALID_STATUSES = %w[registered discovered installing provisioned configured].freeze
      VALID_TRANSITIONS = {
        nil           => %w[registered discovered configured],
        "registered"  => %w[discovered],
        "discovered"  => %w[provisioned installing],
        "installing"  => %w[provisioned],
        "configured"  => %w[installing],
        "provisioned" => %w[configured]
      }.freeze

      attr_accessor :site, :initialized_at
      attr_reader :resume, :hosts, :services, :scanned_hosts

      def self.load(site_name = Pcs.site)
        state_dir = Pcs.state_dir(site_name)
        path = state_dir / "state.yml"
        data = path.exist? ? YAML.safe_load_file(path, symbolize_names: true) : {}
        new(data, path)
      end

      def initialize(data, path)
        @path = path
        @site = data[:site]
        @initialized_at = data[:initialized_at]
        @resume = data[:resume] || { command: nil, phase: nil, data: {} }
        @hosts = (data[:hosts] || {}).transform_keys(&:to_sym)
        @services = (data[:services] || default_services).transform_keys(&:to_sym)
        @scanned_hosts = (data[:scanned_hosts] || {}).transform_keys(&:to_s)
      end

      def initialized? = !site.nil?

      # --- Device state ---

      def host(name)       = hosts[name.to_sym] || {}
      def host_status(name) = host(name)[:status]

      def update_host(name, new_status, **attrs)
        current = host_status(name)
        allowed = VALID_TRANSITIONS[current] || []
        unless allowed.include?(new_status)
          raise "Invalid transition: #{name} cannot go from '#{current || "nil"}' to '#{new_status}'"
        end

        @hosts[name.to_sym] = host(name).merge(
          status: new_status,
          "#{new_status}_at".to_sym => Time.now.iso8601,
          **attrs
        )
      end

      def touch(name)
        return unless hosts.key?(name.to_sym)
        @hosts[name.to_sym] = host(name).merge(last_seen: Time.now.iso8601)
      end

      # --- Service state ---

      def service(name) = services[name.to_sym] || {}
      def service_status(name) = service(name)[:status]

      def update_service(name, new_status, **attrs)
        @services[name.to_sym] = service(name).merge(
          status: new_status,
          **attrs
        )
      end

      def init_services(config)
        config.providers.each do |vertical, provider|
          @services[vertical.to_sym] ||= { status: "unconfigured", provider: provider }
        end
      end

      # --- Discover scan tracking ---

      def record_scanned(ip, mac:, type:)
        @scanned_hosts[ip.to_s] = { mac: mac, type: type.to_s, scanned_at: Time.now.iso8601 }
      end

      def already_scanned?(ip)
        @scanned_hosts.key?(ip.to_s)
      end

      def clear_scanned_hosts
        @scanned_hosts = {}
      end

      # --- Resume ---

      def set_resume(command:, phase:, data: {})
        @resume = { command: command, phase: phase, data: data }
      end

      def clear_resume
        @resume = { command: nil, phase: nil, data: {} }
      end

      def resuming? = !resume[:command].nil?

      # --- Persistence ---

      def save!
        @path.dirname.mkpath
        data = {
          "site" => site,
          "initialized_at" => initialized_at,
          "resume" => deep_stringify(resume),
          "hosts" => hosts.transform_keys(&:to_s).transform_values { |h| h.transform_keys(&:to_s) },
          "services" => services.transform_keys(&:to_s).transform_values { |s| s.transform_keys(&:to_s) },
          "scanned_hosts" => scanned_hosts.transform_keys(&:to_s).transform_values { |h| h.is_a?(Hash) ? h.transform_keys(&:to_s) : h }
        }
        @path.write(YAML.dump(data))
      end

      private

      def deep_stringify(obj)
        case obj
        when Hash then obj.to_h { |k, v| [k.to_s, deep_stringify(v)] }
        when Array then obj.map { |v| deep_stringify(v) }
        else obj
        end
      end

      def default_services
        {
          cluster: { status: "unconfigured" },
          nas: { status: "unconfigured" }
        }
      end
  end
end
