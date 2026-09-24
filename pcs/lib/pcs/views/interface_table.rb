# frozen_string_literal: true

module Pcs
  module Views
    # A table of interfaces, for the host and network pages.
    class InterfaceTable < Termino::View
      def initialize(interfaces:, show: :network) # rubocop:disable Lint/MissingSuper -- Phlex components needn't
        @interfaces = interfaces
        @show = show # the other side: :network on a host's page, :host on a network's
      end

      def view_template
        h2(class: "text-lg font-semibold mt-10 mb-4") { "Interfaces" }
        return p(class: "text-muted-foreground") { "None" } if @interfaces.empty?

        Table do
          TableHeader do
            TableRow { [@show.to_s.humanize, "Name", "MAC", "Vendor", "IP"].each { |h| TableHead { h } } }
          end
          TableBody { @interfaces.each { |iface| row(iface) } }
        end
      end

      private

      def row(iface)
        TableRow do
          TableCell { other_side(iface) }
          TableCell { link(InterfacesResource.record_path(iface), iface.name.presence || "—") }
          [iface.mac, iface.vendor, iface.reachable_ip].each { |text| TableCell { text.to_s } }
        end
      end

      def link(href, text)
        a(href:, class: "underline") { text }
      end

      def other_side(iface)
        if @show == :host
          host = iface.host
          host ? link(HostsResource.record_path(host), host.name) : plain("—")
        else
          plain(iface.network&.name.to_s)
        end
      end
    end
  end
end
