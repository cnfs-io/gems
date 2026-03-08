# frozen_string_literal: true

RSpec.describe Pim::QemuCommandBuilder do
  let(:builder) { described_class.new(arch: 'arm64', memory: 2048, cpus: 2) }

  describe "#add_bridged_net" do
    it "generates a MAC address" do
      builder.add_bridged_net
      cmd = builder.build
      mac_pattern = /52:54:00:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}/
      expect(cmd.join(' ')).to match(mac_pattern)
    end

    it "accepts a custom MAC" do
      builder.add_bridged_net(mac: '52:54:00:aa:bb:cc')
      cmd = builder.build
      expect(cmd.join(' ')).to include('52:54:00:aa:bb:cc')
    end

    context "on macOS" do
      before do
        allow_any_instance_of(described_class).to receive(:macos?).and_return(true)
      end

      it "produces vmnet-bridged args" do
        b = described_class.new(arch: 'arm64', memory: 2048, cpus: 2)
        b.add_drive('/tmp/disk.qcow2')
        b.add_bridged_net(mac: '52:54:00:aa:bb:cc')
        cmd = b.build
        expect(cmd).to include('-nic')
        nic_arg = cmd[cmd.index('-nic') + 1]
        expect(nic_arg).to include('vmnet-bridged')
        expect(nic_arg).to include('52:54:00:aa:bb:cc')
      end
    end

    context "on Linux" do
      before do
        allow_any_instance_of(described_class).to receive(:macos?).and_return(false)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/dev/kvm').and_return(true)
      end

      it "produces bridge netdev args" do
        b = described_class.new(arch: 'arm64', memory: 2048, cpus: 2)
        b.add_drive('/tmp/disk.qcow2')
        b.add_bridged_net(mac: '52:54:00:aa:bb:cc')
        cmd = b.build
        expect(cmd.join(' ')).to include('bridge,id=net0,br=br0')
        expect(cmd.join(' ')).to include('52:54:00:aa:bb:cc')
      end

      it "accepts a custom bridge name" do
        b = described_class.new(arch: 'arm64', memory: 2048, cpus: 2)
        b.add_drive('/tmp/disk.qcow2')
        b.add_bridged_net(bridge: 'br1', mac: '52:54:00:aa:bb:cc')
        cmd = b.build
        expect(cmd.join(' ')).to include('bridge,id=net0,br=br1')
      end
    end
  end

  describe "#add_user_net" do
    it "produces user netdev with port forwarding" do
      builder.add_drive('/tmp/disk.qcow2')
      builder.add_user_net(host_port: 2222)
      cmd = builder.build
      expect(cmd.join(' ')).to include('user,id=net0,hostfwd=tcp::2222-:22')
    end
  end
end
