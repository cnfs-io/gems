# frozen_string_literal: true

module Pcs
  module Commands
    # `pcs new sg`: a project for one site, with the site, the networks this
    # machine is on, and this machine as the site's control plane.
    class NewSite < Termino::Commands::NewProject
      desc "Create a site project (run on the site's control plane)"
      option :domain, desc: "DNS domain for the site's hosts (default: <name>.lan)"
      option :timezone, desc: "The site's timezone (default: this machine's)"

      private

      def setup(root, domain: nil, timezone: nil, **)
        name = File.basename(root)
        site = Site.create!(name:, domain: domain || "#{name}.lan", timezone: timezone || local.timezone)
        networks = create_networks(site)
        create_control_plane(site, networks)
        networks.each_value { |network| puts "  network #{network.name}: #{network.subnet}" }
        puts "  control plane: #{local.hostname}"
      end

      # One network per subnet this machine is on; the first is primary.
      def create_networks(site)
        local.interfaces.uniq(&:subnet).each_with_index.to_h do |iface, index|
          network = Network.create!(site_id: site.id, name: index.zero? ? "primary" : iface.name,
                                    subnet: iface.subnet, primary: index.zero?)
          [iface.subnet, network]
        end
      end

      # This machine: already installed, so already provisioned.
      def create_control_plane(site, networks)
        cp = DebianHost.create!(site_id: site.id, hostname: local.hostname, role: "cp", arch: local.arch,
                                status: "provisioned")
        create_interfaces(cp, networks)
      end

      def create_interfaces(host, networks)
        local.interfaces.each do |iface|
          Interface.create!(host_id: host.id, network_id: networks.fetch(iface.subnet).id, name: iface.name,
                            mac: iface.mac, configured_ip: iface.ip)
        end
      end

      def local
        Local
      end
    end
  end
end
