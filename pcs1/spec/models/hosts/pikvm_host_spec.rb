# frozen_string_literal: true

RSpec.describe Pcs1::PikvmHost do
  before do
    TestProject.seed_all(test_dir,
      host: { "hostname" => "kvm1", "type" => "pikvm", "role" => "kvm",
              "arch" => "arm64", "status" => "keyed", "connect_as" => "root" })
  end

  let(:host) { Pcs1::Host.first }
  let(:mock_ssh) { instance_double("Net::SSH::Connection::Session") }

  before do
    allow(mock_ssh).to receive(:exec!).and_return("")
    allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
  end

  describe "#restart_networking!" do
    it "reboots the host via SSH" do
      host.restart_networking!
      expect(mock_ssh).to have_received(:exec!).with("reboot")
    end
  end

  describe ".detect?" do
    it "returns true when kvmd is active" do
      ssh = double("ssh")
      allow(ssh).to receive(:exec!).with("systemctl is-active kvmd").and_return("active\n")
      expect(Pcs1::PikvmHost.detect?(ssh)).to be true
    end

    it "returns false when kvmd is not active" do
      ssh = double("ssh")
      allow(ssh).to receive(:exec!).with("systemctl is-active kvmd").and_return("inactive\n")
      expect(Pcs1::PikvmHost.detect?(ssh)).to be false
    end
  end
end
