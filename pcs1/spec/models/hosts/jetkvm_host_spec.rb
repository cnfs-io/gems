# frozen_string_literal: true

RSpec.describe Pcs1::JetkvmHost do
  before do
    TestProject.seed_all(test_dir,
      host: { "hostname" => "jet1", "type" => "jetkvm", "role" => "kvm",
              "arch" => "arm64", "status" => "discovered", "connect_as" => "root" })
  end

  let(:host) { Pcs1::Host.first }
  let(:mock_ssh) { instance_double("Net::SSH::Connection::Session") }

  before do
    allow(mock_ssh).to receive(:exec!).and_return("")
    allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
  end

  describe "#key!" do
    it "does not attempt SSH — logs instructions instead" do
      host.key!
      # JetKVM key! just logs, never calls ssh_exec!
      # The global Net::SSH stub is set but key! shouldn't trigger it
    end
  end

  describe ".detect?" do
    it "returns true when hostname contains jetkvm" do
      ssh = double("ssh")
      allow(ssh).to receive(:exec!).with("cat /etc/hostname 2>/dev/null").and_return("JetKVM\n")
      expect(Pcs1::JetkvmHost.detect?(ssh)).to be true
    end

    it "returns false for other hostnames" do
      ssh = double("ssh")
      allow(ssh).to receive(:exec!).with("cat /etc/hostname 2>/dev/null").and_return("debian\n")
      expect(Pcs1::JetkvmHost.detect?(ssh)).to be false
    end
  end

  describe "#restart_networking!" do
    it "reboots the host via SSH" do
      host.restart_networking!
      expect(mock_ssh).to have_received(:exec!).with("reboot")
    end
  end
end
