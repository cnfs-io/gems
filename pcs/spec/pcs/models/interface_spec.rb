# frozen_string_literal: true

RSpec.describe Pcs::Interface, :uses_fixture_project do
  describe ".load" do
    it "loads interfaces for a site" do
      interfaces = Pcs::Interface.load("sg")
      expect(interfaces.size).to eq(9)
    end
  end

  describe "#host" do
    it "belongs to a host" do
      iface = Pcs::Interface.load("sg").first
      expect(iface.host).to be_a(Pcs::Host)
    end
  end

  describe "#network" do
    it "belongs to a network" do
      iface = Pcs::Interface.load("sg").first
      expect(iface.network).to be_a(Pcs::Network)
    end
  end

  describe "#network_name" do
    it "delegates to network" do
      iface = Pcs::Interface.find_by(host_id: "6", network_id: "1", site_id: "sg")
      expect(iface.network_name).to eq("compute")
    end
  end

  describe "attributes" do
    let(:iface) { Pcs::Interface.find_by(host_id: "6", network_id: "1", site_id: "sg") }

    it "has name" do
      expect(iface.name).to eq("enp2s0")
    end

    it "has mac" do
      expect(iface.mac).to eq("70:70:fc:05:2d:69")
    end

    it "has ip" do
      expect(iface.ip).to eq("172.31.1.41")
    end
  end
end
