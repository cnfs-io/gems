# frozen_string_literal: true

RSpec.describe Pcs::Site, :uses_fixture_project do
  let(:site) { Pcs::Site.find_by(name: "sg") }

  describe ".load" do
    it "loads site by name" do
      loaded = Pcs::Site.load("sg")
      expect(loaded).not_to be_nil
      expect(loaded.name).to eq("sg")
    end
  end

  describe ".find_by" do
    it "finds site by name" do
      expect(site).not_to be_nil
      expect(site.name).to eq("sg")
    end

    it "returns nil for nonexistent site" do
      expect(Pcs::Site.find_by(name: "nonexistent")).to be_nil
    end
  end

  describe "attribute accessors" do
    it "returns domain" do
      expect(site.domain).to eq("sg.me.internal")
    end

    it "returns timezone" do
      expect(site.timezone).to eq("Asia/Singapore")
    end

    it "returns ssh_key" do
      expect(site.ssh_key).to eq("~/.ssh/authorized_keys")
    end
  end

  describe "#network" do
    it "returns compute network as Network model" do
      compute = site.network(:compute)
      expect(compute).to be_a(Pcs::Network)
      expect(compute.subnet).to eq("172.31.1.0/24")
      expect(compute.gateway).to eq("172.31.1.1")
      expect(compute.dns_resolvers).to eq(["172.31.1.1", "1.1.1.1", "8.8.8.8"])
    end

    it "returns storage network" do
      storage = site.network(:storage)
      expect(storage).to be_a(Pcs::Network)
      expect(storage.subnet).to eq("172.31.2.0/24")
      expect(storage.gateway).to eq("172.31.2.1")
    end

    it "returns nil for unknown network" do
      expect(site.network(:unknown)).to be_nil
    end
  end

  describe "#primary_network" do
    it "returns the primary network" do
      primary = site.primary_network
      expect(primary).to be_a(Pcs::Network)
      expect(primary.name).to eq("compute")
      expect(primary.primary).to eq(true)
    end
  end

  describe "has_many :networks" do
    it "returns all networks for the site" do
      networks = site.networks
      expect(networks.size).to eq(2)
      expect(networks.map(&:name)).to contain_exactly("compute", "storage")
    end
  end

  describe "#update" do
    it "changes a top-level value via hash" do
      site.update(timezone: "UTC")
      expect(site.timezone).to eq("UTC")
    end
  end

  describe ".top_level_domain" do
    it "returns configured top_level_domain" do
      expect(Pcs::Site.top_level_domain).to eq("me.internal")
    end

    it "allows overriding" do
      original = Pcs::Site.top_level_domain
      Pcs::Site.top_level_domain = "test.internal"
      expect(Pcs::Site.top_level_domain).to eq("test.internal")
    ensure
      Pcs::Site.top_level_domain = original
    end
  end

  describe "SSH helpers" do
    it "derives ssh_key_path from ssh_key" do
      expect(site.ssh_key_path).to be_a(Pathname)
      expect(site.ssh_key_path.to_s).to end_with("authorized_keys")
    end

    it "derives public key path by appending .pub" do
      expect(site.ssh_public_key_path.to_s).to end_with("authorized_keys.pub")
    end

    it "derives private key path by removing .pub extension" do
      s = Pcs::Site.new(name: "test", ssh_key: "~/.ssh/id_ed25519.pub")
      expect(s.ssh_private_key_path.to_s).to end_with("id_ed25519")
    end

    it "returns nil when ssh_key is nil" do
      s = Pcs::Site.new(name: "test")
      expect(s.ssh_key_path).to be_nil
      expect(s.ssh_private_key_path).to be_nil
      expect(s.ssh_public_key_path).to be_nil
    end
  end

  describe "#save!" do
    it "writes valid YAML and round-trips" do
      site.update(timezone: "UTC")
      site.save!

      Pcs::Site.reload!
      reloaded = Pcs::Site.find_by(name: "sg")
      expect(reloaded.timezone).to eq("UTC")
    end
  end
end
