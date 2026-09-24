# frozen_string_literal: true

module Records
  def site
    @site ||= Pcs::Site.create!(name: "sg", domain: "sg.lan", timezone: "Asia/Singapore")
  end

  def network
    @network ||= Pcs::Network.create!(site_id: site.id, name: "primary", subnet: "10.0.0.0/24", primary: true,
                                      gateway: "10.0.0.1")
  end

  # This machine, which serves installs on the network at 10.0.0.2.
  def control_plane
    @control_plane ||= host(Pcs::DebianHost, hostname: "cp", role: "cp", status: "provisioned", mac: nil,
                                             discovered_ip: nil, configured_ip: "10.0.0.2")
  end

  # A host with one interface on the primary network.
  def host(klass = Pcs::Host, mac: "aa:bb:cc:00:00:01", discovered_ip: "10.0.0.50", configured_ip: nil, **attrs)
    klass.create!(site_id: site.id, **attrs).tap do |h|
      Pcs::Interface.create!(host_id: h.id, network_id: network.id, mac:, discovered_ip:, configured_ip:)
    end
  end
end

RSpec.configure { |c| c.include Records }
