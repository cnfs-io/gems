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
        expect(nic_arg).to include('ifname=en0')
        expect(nic_arg).to include('52:54:00:aa:bb:cc')
      end

      it "bridges the given interface" do
        b = described_class.new(arch: 'arm64', memory: 2048, cpus: 2)
        b.add_bridged_net(bridge: 'en7')
        cmd = b.build
        expect(cmd[cmd.index('-nic') + 1]).to include('ifname=en7')
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

  describe "#set_cdrom" do
    it "attaches the ISO as a SCSI CD-ROM on arm64" do
      builder.set_cdrom('/tmp/debian.iso')
      cmd = builder.build
      expect(cmd).not_to include('-cdrom')
      expect(cmd).to include('file=/tmp/debian.iso,media=cdrom,if=none,id=cd0,readonly=on')
      expect(cmd).to include('scsi-cd,drive=cd0,bus=scsi0.0')
    end

    it "uses -cdrom on x86_64" do
      b = described_class.new(arch: 'x86_64', memory: 2048, cpus: 2)
      b.set_cdrom('/tmp/debian.iso')
      cmd = b.build
      expect(cmd[cmd.index('-cdrom') + 1]).to eq('/tmp/debian.iso')
    end
  end

  describe "#add_usb_disk" do
    it "attaches each disk as USB storage on one xhci controller, after the NIC" do
      builder.add_user_net(host_port: 2222)
      builder.add_usb_disk('/dev/rdisk5').add_usb_disk('/dev/rdisk4')
      cmd = builder.build

      expect(cmd.count('qemu-xhci,id=xhci')).to eq(1)
      expect(cmd).to include('file=/dev/rdisk5,format=raw,if=none,id=usbdisk0')
      expect(cmd).to include('usb-storage,bus=xhci.0,drive=usbdisk1,removable=on')
      expect(cmd.index('qemu-xhci,id=xhci')).to be > cmd.index('virtio-net-pci,netdev=net0,addr=0x1')
    end

    it "adds no USB controller without disks" do
      expect(builder.build).not_to include('qemu-xhci,id=xhci')
    end
  end

  describe "#add_share" do
    it "adds a 9p fsdev and device per share, after the NIC" do
      builder.add_user_net(host_port: 2222)
      builder.add_share('/Users/me/code', tag: 'code').add_share('/Users/me/a,b', tag: 'ab', readonly: true)
      cmd = builder.build

      expect(cmd).to include('local,id=fs0,path=/Users/me/code,security_model=none')
      expect(cmd).to include('virtio-9p-pci,fsdev=fs0,mount_tag=code')
      expect(cmd).to include('local,id=fs1,path=/Users/me/a,,b,security_model=none,readonly=on')
      expect(cmd.index('-fsdev')).to be > cmd.index('virtio-net-pci,netdev=net0,addr=0x1')
    end
  end

  describe "#add_user_net" do
    it "produces user netdev with port forwarding" do
      builder.add_drive('/tmp/disk.qcow2')
      builder.add_user_net(host_port: 2222)
      cmd = builder.build
      expect(cmd.join(' ')).to include('user,id=net0,hostfwd=tcp::2222-:22')
    end

    it "pins the NIC to PCI slot 1 on arm64, ahead of the CD-ROM controller" do
      builder.set_cdrom('/tmp/debian.iso')
      builder.add_user_net(host_port: 2222)
      cmd = builder.build
      nic = cmd.index('virtio-net-pci,netdev=net0,addr=0x1')
      expect(nic).not_to be_nil
      expect(nic).to be < cmd.index('virtio-scsi-pci,id=scsi0')
    end

    it "does not pin the NIC on x86_64" do
      b = described_class.new(arch: 'x86_64', memory: 2048, cpus: 2)
      b.add_user_net(host_port: 2222)
      expect(b.build).to include('virtio-net-pci,netdev=net0')
    end
  end
end
