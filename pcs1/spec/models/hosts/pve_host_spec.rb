# frozen_string_literal: true

RSpec.describe Pcs1::PveHost do
  before do
    TestProject.seed_all(test_dir,
      host: { "hostname" => "pve1", "type" => "proxmox", "role" => "hypervisor",
              "arch" => "amd64", "status" => "provisioned", "pve_status" => "pending",
              "connect_as" => "root" })
  end

  let(:host) { Pcs1::Host.first }
  let(:mock_ssh) { instance_double("Net::SSH::Connection::Session") }

  before do
    allow(mock_ssh).to receive(:exec!).and_return("")
    allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
  end

  describe "pve_status state machine" do
    it "starts in pending state" do
      expect(host.pve_status).to eq("pending")
    end

    describe "install_pve event" do
      it "transitions from pending to pve_installed when verified" do
        allow(host).to receive(:pve_install_verified?).and_return(true)
        expect(host.fire_pve_status_event(:install_pve)).to be_truthy
        expect(host.pve_status).to eq("pve_installed")
      end

      it "blocks when pve_install_verified? is false" do
        allow(host).to receive(:pve_install_verified?).and_return(false)
        expect(host.fire_pve_status_event(:install_pve)).to be_falsey
        expect(host.pve_status).to eq("pending")
      end
    end

    describe "validate_networks event" do
      before { host.pve_status = "pve_installed" }

      it "transitions from pve_installed to networks_validated when valid" do
        allow(host).to receive(:networks_valid?).and_return(true)
        expect(host.fire_pve_status_event(:validate_networks)).to be_truthy
        expect(host.pve_status).to eq("networks_validated")
      end

      it "blocks when networks_valid? is false" do
        allow(host).to receive(:networks_valid?).and_return(false)
        expect(host.fire_pve_status_event(:validate_networks)).to be_falsey
        expect(host.pve_status).to eq("pve_installed")
      end
    end

    describe "join_cluster event" do
      it "transitions from networks_validated to clustered" do
        host.pve_status = "networks_validated"
        expect(host.fire_pve_status_event(:join_cluster)).to be_truthy
        expect(host.pve_status).to eq("clustered")
      end

      it "does not transition from pending" do
        expect(host.fire_pve_status_event(:join_cluster)).to be_falsey
        expect(host.pve_status).to eq("pending")
      end
    end
  end

  describe ".detect?" do
    it "returns true when pveversion is present" do
      ssh = double("ssh")
      allow(ssh).to receive(:exec!).with("pveversion 2>/dev/null").and_return("pve-manager/8.0.4")
      expect(Pcs1::PveHost.detect?(ssh)).to be true
    end

    it "returns false when pveversion is not found" do
      ssh = double("ssh")
      allow(ssh).to receive(:exec!).with("pveversion 2>/dev/null").and_return(nil)
      expect(Pcs1::PveHost.detect?(ssh)).to be false
    end
  end

  describe "#restart_networking!" do
    it "attempts ifreload then falls back" do
      host.restart_networking!
      expect(mock_ssh).to have_received(:exec!).with("ifreload -a 2>/dev/null || systemctl restart networking")
    end
  end
end
