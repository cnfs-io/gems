# frozen_string_literal: true

RSpec.describe Pcs::Network, :uses_fixture_project do
  describe ".load" do
    it "loads networks for a site" do
      networks = Pcs::Network.load("sg")
      expect(networks.size).to eq(2)
    end
  end

  describe ".primary" do
    it "finds primary network" do
      primary = Pcs::Network.primary("sg")
      expect(primary.name).to eq("compute")
      expect(primary.primary).to eq(true)
    end
  end

  describe ".find_by_name" do
    it "finds by name" do
      net = Pcs::Network.find_by_name("storage", site_name: "sg")
      expect(net.subnet).to eq("172.31.2.0/24")
    end

    it "returns nil for unknown name" do
      expect(Pcs::Network.find_by_name("unknown", site_name: "sg")).to be_nil
    end
  end

  describe "#contains_ip?" do
    it "returns true for IP in subnet" do
      net = Pcs::Network.find_by_name("compute", site_name: "sg")
      expect(net.contains_ip?("172.31.1.50")).to eq(true)
    end

    it "returns false for IP outside subnet" do
      net = Pcs::Network.find_by_name("compute", site_name: "sg")
      expect(net.contains_ip?("172.31.2.50")).to eq(false)
    end
  end

  describe "#site" do
    it "returns the parent site" do
      net = Pcs::Network.find_by_name("compute", site_name: "sg")
      expect(net.site).to be_a(Pcs::Site)
      expect(net.site.name).to eq("sg")
    end
  end

  describe "attributes" do
    let(:compute) { Pcs::Network.find_by_name("compute", site_name: "sg") }

    it "has name" do
      expect(compute.name).to eq("compute")
    end

    it "has subnet" do
      expect(compute.subnet).to eq("172.31.1.0/24")
    end

    it "has gateway" do
      expect(compute.gateway).to eq("172.31.1.1")
    end

    it "has dns_resolvers" do
      expect(compute.dns_resolvers).to eq(["172.31.1.1", "1.1.1.1", "8.8.8.8"])
    end

    it "has primary flag" do
      expect(compute.primary).to eq(true)
    end

    it "has site_id" do
      expect(compute.site_id).to eq("sg")
    end
  end
end
