# frozen_string_literal: true

module Pcs
  module Views
    # The site at a glance: where it is, and how far along its hosts are.
    class Home < Termino::View
      def view_template
        render Layout.new(title: site ? "pcs: #{site.name}" : "pcs") do
          site ? overview : p { "This project has no site; create projects with `pcs new`." }
        end
      end

      private

      def site
        @site ||= Site.first
      end

      def overview
        h1(class: "text-2xl font-semibold mb-2") { site.name }
        p(class: "text-muted-foreground mb-8") { "#{site.domain} · #{site.timezone}" }
        dl(class: "grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2") do
          count("Networks", Network.count, NetworksResource.index_path)
          Host.all.group_by(&:status).sort.each do |status, hosts|
            count("Hosts #{status}", hosts.size, HostsResource.index_path)
          end
        end
      end

      def count(label, number, href)
        dt(class: "font-medium") { label }
        dd { a(href:, class: "underline") { number.to_s } }
      end
    end
  end
end
