# frozen_string_literal: true

module Pcs
  module Service
    # Services that are managed via the CLI (start/stop/reload/status).
    # ControlPlane is excluded — it's used internally by cp_command, not as a managed service.
    MANAGED = %i[Dnsmasq Netboot].freeze

    def self.resolve(name)
      class_name = name.to_s.capitalize.to_sym
      const_get(class_name)
    rescue NameError
      raise ArgumentError, "Unknown service '#{name}'. Known: #{managed_names.join(", ")}"
    end

    def self.managed
      MANAGED.map { |name| [name.to_s.downcase, const_get(name)] }
    end

    def self.managed_names
      MANAGED.map { |name| name.to_s.downcase }
    end
  end
end
