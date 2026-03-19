# frozen_string_literal: true

RSpec.describe Pcs1::Dnsmasq do
  before do
    TestProject.seed_all(test_dir,
      host: { "hostname" => "ops1", "type" => "debian", "role" => "control",
              "arch" => "arm64", "status" => "configured" })
    # ops1 is local — its IP matches
    allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["172.31.1.20"])
    # Configure dnsmasq to write to temp dir
    Pcs1.configure do |c|
      c.dnsmasq.config_path = File.join(test_dir, "dnsmasq.conf")
    end
  end

  describe ".prefix_to_netmask" do
    it "converts /24 correctly" do
      expect(Pcs1::Dnsmasq.prefix_to_netmask(24)).to eq("255.255.255.0")
    end

    it "converts /16 correctly" do
      expect(Pcs1::Dnsmasq.prefix_to_netmask(16)).to eq("255.255.0.0")
    end

    it "converts /8 correctly" do
      expect(Pcs1::Dnsmasq.prefix_to_netmask(8)).to eq("255.0.0.0")
    end

    it "converts /32 correctly" do
      expect(Pcs1::Dnsmasq.prefix_to_netmask(32)).to eq("255.255.255.255")
    end
  end

  describe ".ops_ip_for" do
    it "finds the local host's configured IP on the network" do
      network = Pcs1::Network.first
      expect(Pcs1::Dnsmasq.ops_ip_for(network)).to eq("172.31.1.20")
    end

    it "returns nil when no local host on network" do
      allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["10.0.0.1"])
      network = Pcs1::Network.first
      expect(Pcs1::Dnsmasq.ops_ip_for(network)).to be_nil
    end
  end

  describe ".build_reservations" do
    it "includes interfaces with mac and configured_ip" do
      network = Pcs1::Network.first
      reservations = Pcs1::Dnsmasq.build_reservations(network)
      expect(reservations.size).to eq(1)
      expect(reservations.first[:mac]).to eq("aa:bb:cc:dd:ee:ff")
      expect(reservations.first[:ip]).to eq("172.31.1.20")
      expect(reservations.first[:hostname]).to eq("ops1")
    end

    it "excludes interfaces without configured_ip" do
      iface = Pcs1::Interface.first
      iface.configured_ip = nil
      iface.save!
      network = Pcs1::Network.first
      reservations = Pcs1::Dnsmasq.build_reservations(network)
      expect(reservations).to be_empty
    end

    it "excludes interfaces without mac" do
      iface = Pcs1::Interface.first
      iface.mac = nil
      iface.save!
      network = Pcs1::Network.first
      reservations = Pcs1::Dnsmasq.build_reservations(network)
      expect(reservations).to be_empty
    end

    it "excludes interfaces whose host has no hostname" do
      host = Pcs1::Host.first
      host.hostname = nil
      host.save!
      network = Pcs1::Network.first
      reservations = Pcs1::Dnsmasq.build_reservations(network)
      expect(reservations).to be_empty
    end
  end

  describe ".render_config" do
    it "produces valid dnsmasq config" do
      config = Pcs1::Dnsmasq.render_config
      expect(config).to include("port=0")
      expect(config).to include("interface=eth0")
      expect(config).to include("dhcp-range=")
      expect(config).to include("dhcp-host=aa:bb:cc:dd:ee:ff,172.31.1.20,ops1")
    end

    it "raises when no primary network exists" do
      TestProject.seed_network(test_dir, "primary" => false)
      Pcs1::Network.reload!
      expect { Pcs1::Dnsmasq.render_config }.to raise_error(RuntimeError, /No primary network/)
    end
  end

  describe ".reconcile!" do
    it "writes config and restarts when config is new" do
      expect(Pcs1::Platform).to receive(:sudo_write)
      expect(Pcs1::Platform).to receive(:system_cmd).with("sudo systemctl restart dnsmasq", raise_on_error: true)
      result = Pcs1::Dnsmasq.reconcile!
      expect(result).to be true
    end

    it "skips restart when config is unchanged" do
      # Write initial config
      config_path = Pcs1.config.dnsmasq.config_path
      config = Pcs1::Dnsmasq.render_config
      File.write(config_path, config)

      expect(Pcs1::Platform).not_to receive(:sudo_write)
      result = Pcs1::Dnsmasq.reconcile!
      expect(result).to be false
    end
  end
end
