# frozen_string_literal: true

module Pcs
  module Operations
    # Marks a host configured once pcs knows everything it needs (type,
    # hostname, address, disk...), and writes its netboot files.
    class Configure < HostOperation
      private

      def perform
        check_configurable!
        step("mark #{host.name} configured") { host.configure! }
        reconcile if host.pxe?
        host
      end

      def check_configurable!
        missing = host.missing_configuration
        raise Pcs::Error, "#{host.name} still needs: #{describe(missing)}" if missing.any?
        raise Pcs::Error, "#{host.name} is #{host.status} and can't be configured now" unless host.can_configure?
      end

      def describe(names) = names.map { |name| name.to_s.humanize(capitalize: false) }.join(", ")
    end
  end
end
