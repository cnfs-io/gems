# frozen_string_literal: true

RSpec.describe Pcs1::Host do
  before do
    TestProject.seed_all(test_dir,
      host: { "hostname" => "node1", "role" => "compute", "type" => "debian",
              "arch" => "amd64", "status" => "discovered" })
  end

  let(:host) { Pcs1::Host.first }

  describe "#configuration_complete?" do
    it "returns true when all required fields are set" do
      host.hostname = "node1"
      host.role = "compute"
      host.type = "debian"
      host.arch = "amd64"
      expect(host.configuration_complete?).to be true
    end

    it "returns false when hostname is missing" do
      host.hostname = nil
      expect(host.configuration_complete?).to be false
    end

    it "returns false when role is missing" do
      host.role = nil
      expect(host.configuration_complete?).to be false
    end

    it "returns false when type is missing" do
      host.type = nil
      expect(host.configuration_complete?).to be false
    end

    it "returns false when arch is missing" do
      host.arch = nil
      expect(host.configuration_complete?).to be false
    end

    it "returns false when no interfaces exist" do
      # Remove the interface
      Pcs1::Interface.all.each(&:destroy)
      Pcs1::Interface.reload!
      host.reload if host.respond_to?(:reload)
      expect(host.configuration_complete?).to be false
    end

    it "returns false when an interface has no configured_ip" do
      iface = Pcs1::Interface.first
      iface.configured_ip = nil
      iface.save!
      expect(host.configuration_complete?).to be false
    end

    it "returns false when an interface has no name" do
      iface = Pcs1::Interface.first
      iface.name = nil
      iface.save!
      expect(host.configuration_complete?).to be false
    end
  end

  describe "#local?" do
    it "returns true when a host interface IP matches a local IP" do
      allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["172.31.1.20"])
      expect(host.local?).to be true
    end

    it "returns true when discovered_ip matches a local IP" do
      allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["172.31.1.100"])
      expect(host.local?).to be true
    end

    it "returns false when no IPs match" do
      allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["10.0.0.1"])
      expect(host.local?).to be false
    end
  end

  describe "#pxe_target?" do
    before do
      allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["10.0.0.1"])
    end

    it "returns false when pxe_boot is false" do
      host.pxe_boot = false
      expect(host.pxe_target?).to be false
    end

    it "returns false when host is local" do
      allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["172.31.1.20"])
      host.pxe_boot = true
      expect(host.pxe_target?).to be false
    end

    it "returns true for a PXE-capable, non-local host" do
      host.pxe_boot = true
      expect(host.pxe_target?).to be true
    end
  end

  describe "#connect_user" do
    it "returns connect_as when set" do
      host.connect_as = "admin"
      expect(host.connect_user).to eq("admin")
    end

    it "falls back to host_defaults" do
      Pcs1.configure do |c|
        c.host_defaults = { "debian" => { user: "debian-user" } }
      end
      host.connect_as = nil
      expect(host.connect_user).to eq("debian-user")
    end
  end

  describe "#connect_pass" do
    it "returns connect_password when set" do
      host.connect_password = "secret"
      expect(host.connect_pass).to eq("secret")
    end

    it "falls back to host_defaults" do
      Pcs1.configure do |c|
        c.host_defaults = { "debian" => { password: "default-pass" } }
      end
      host.connect_password = nil
      expect(host.connect_pass).to eq("default-pass")
    end
  end

  describe "state machine" do
    it "starts in discovered state" do
      expect(host.status).to eq("discovered")
    end

    describe "key event" do
      before do
        allow(host).to receive(:key_access?).and_return(true)
      end

      it "transitions from discovered to keyed when key_access? is true" do
        expect(host.fire_status_event(:key)).to be_truthy
        expect(host.status).to eq("keyed")
      end

      it "does not transition when key_access? is false" do
        allow(host).to receive(:key_access?).and_return(false)
        expect(host.fire_status_event(:key)).to be_falsey
        expect(host.status).to eq("discovered")
      end
    end

    describe "configure event" do
      before do
        host.status = "keyed"
        allow(host).to receive(:configuration_complete?).and_return(true)
      end

      it "transitions from keyed to configured" do
        expect(Pcs1::Dnsmasq).to receive(:reconcile!)
        expect(Pcs1::Netboot).to receive(:reconcile!)
        expect(host.fire_status_event(:configure)).to be_truthy
        expect(host.status).to eq("configured")
      end

      it "fires site.reconcile! after transition to configured" do
        expect(Pcs1::Dnsmasq).to receive(:reconcile!)
        expect(Pcs1::Netboot).to receive(:reconcile!)
        host.fire_status_event(:configure)
      end

      it "does not transition when configuration_complete? is false" do
        allow(host).to receive(:configuration_complete?).and_return(false)
        expect(host.fire_status_event(:configure)).to be_falsey
        expect(host.status).to eq("keyed")
      end
    end

    describe "provision event" do
      it "transitions from configured to provisioned" do
        host.status = "configured"
        expect(host.fire_status_event(:provision)).to be_truthy
        expect(host.status).to eq("provisioned")
      end

      it "does not transition from discovered" do
        expect(host.fire_status_event(:provision)).to be_falsey
        expect(host.status).to eq("discovered")
      end
    end
  end

  describe "#ready_to_key?" do
    before do
      Pcs1.configure do |c|
        c.host_defaults = { "debian" => { user: "admin", password: "pass" } }
      end
    end

    it "returns true when credentials and reachable interface exist" do
      expect(host.ready_to_key?).to be true
    end

    it "returns false when connect_user is blank" do
      Pcs1.configure do |c|
        c.host_defaults = {}
      end
      host.connect_as = nil
      expect(host.ready_to_key?).to be false
    end
  end
end
