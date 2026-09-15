# frozen_string_literal: true

require 'tempfile'

RSpec.describe Pim::VmRunner do
  let(:profile) { instance_double(Pim::Profile, id: "default", resolve: "pim") }
  let(:build) do
    instance_double(Pim::Build,
                    id: "dev-debian",
                    resolved_profile: profile,
                    arch: "arm64",
                    memory: 2048,
                    cpus: 2,
                    ssh_user: "ansible")
  end

  let(:vm_registry) { instance_double(Pim::VmRegistry) }

  before do
    allow(Pim::VmRegistry).to receive(:new).and_return(vm_registry)
    allow(vm_registry).to receive(:register).and_return("dev-debian")
    allow(vm_registry).to receive(:unregister)
    allow(vm_registry).to receive(:update)
    allow(vm_registry).to receive(:list).and_return([])
  end

  subject { described_class.new(build: build) }

  describe "#initialize" do
    it "accepts a build and extracts profile, arch, name" do
      runner = described_class.new(build: build)
      expect(runner).to be_a(described_class)
    end

    it "accepts a custom name" do
      runner = described_class.new(build: build, name: "my-vm")
      expect(runner).to be_a(described_class)
    end
  end

  # Shared setup for booting against a fake golden image with QemuVM stubbed out
  shared_context "bootable" do
    let(:golden_image) { "/tmp/images/default-arm64.qcow2" }
    let(:registry) { instance_double(Pim::Registry) }
    let(:data_home) { Dir.mktmpdir }
    let(:vm_disk) { File.join(data_home, "vms", "dev-debian.qcow2") }
    let(:vm) { instance_double(Pim::QemuVM, pid: 123, running?: true) }
    let(:commands) { [] }

    before do
      allow(Pim::Registry).to receive(:new).and_return(registry)
      allow(registry).to receive(:find_legacy).and_return({ 'path' => golden_image })
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(golden_image).and_return(true)
      allow(Pim).to receive(:data_home).and_return(data_home)
      allow(Pim::Qemu).to receive(:find_available_port).and_return(2222)
      allow(Pim::Qemu).to receive(:find_efi_firmware).and_return(nil)
      allow(Pim::Qemu).to receive(:runtime_dir).and_return('/tmp/pim')
      allow(Pim::Qemu).to receive(:default_interface).and_return('en0')
      allow(Pim::QemuVM).to receive(:new) { |args| commands << args[:command]; vm }
      allow(vm).to receive(:start_background).and_return(vm)
      allow(subject).to receive(:discover_ip).and_return(nil)
      allow(subject).to receive(:claim_agent_socket)
      allow(subject).to receive(:system).with('sudo', '-v').and_return(true)
    end

    after { FileUtils.remove_entry(data_home) }
  end

  describe "disk modes" do
    include_context "bootable"

    it "snapshot boots the golden image with -snapshot" do
      expect { subject.run(disk: 'snapshot', network: 'host') }.to output(/VM:/).to_stdout
      expect(subject.image_path).to eq(golden_image)
      expect(commands.last).to include('-snapshot')
    end

    it "overlay creates a persistent overlay named after the VM" do
      expect(Pim::QemuDiskImage).to receive(:create_overlay).with(golden_image, vm_disk)

      expect { subject.run(disk: 'overlay', network: 'host') }.to output(/VM:/).to_stdout
      expect(subject.image_path).to eq(vm_disk)
      expect(commands.last).not_to include('-snapshot')
    end

    it "clone copies the golden image on first run" do
      expect(Pim::QemuDiskImage).to receive(:clone).with(golden_image, vm_disk)

      expect { subject.run(disk: 'clone', network: 'host') }.to output(/Cloning/).to_stdout
    end

    it "clone reuses the existing VM disk on later runs" do
      FileUtils.mkdir_p(File.dirname(vm_disk))
      File.write(vm_disk, "disk")
      expect(Pim::QemuDiskImage).not_to receive(:clone)

      expect { subject.run(disk: 'clone', network: 'host') }.to output(/Using existing VM disk/).to_stdout
    end

    it "fresh re-clones an existing VM disk" do
      FileUtils.mkdir_p(File.dirname(vm_disk))
      File.write(vm_disk, "disk")
      expect(Pim::QemuDiskImage).to receive(:clone).with(golden_image, vm_disk)

      expect { subject.run(disk: 'clone', network: 'host', fresh: true) }.to output(/Cloning/).to_stdout
      expect(File.exist?(vm_disk)).to be false # removed before cloning (clone is stubbed)
    end

    it "refuses a disk that a running VM is using" do
      allow(vm_registry).to receive(:list).and_return([{ 'name' => 'dev-debian', 'image_path' => vm_disk }])

      expect { subject.run(disk: 'clone', network: 'host') }
        .to raise_error(Pim::VmRunner::Error, /in use by 'dev-debian'/)
    end

    it "rejects unknown modes" do
      expect { subject.run(disk: 'bogus') }.to raise_error(Pim::VmRunner::Error, /Unknown disk mode/)
      expect { subject.run(network: 'user') }.to raise_error(Pim::VmRunner::Error, /Unknown network/)
    end
  end

  describe "USB passthrough" do
    include_context "bootable"

    before do
      allow(subject).to receive(:macos?).and_return(true)
      allow(Pim::UsbDisk).to receive(:resolve).with('058f:6387').and_return('/dev/disk5')
      allow(Pim::UsbDisk).to receive(:release)
      allow(Pim::UsbDisk).to receive(:qemu_path).with('/dev/disk5').and_return('/dev/rdisk5')
    end

    it "releases the disk and attaches it as USB storage under sudo" do
      expect(Pim::UsbDisk).to receive(:release).with('/dev/disk5')

      expect { subject.run(disk: 'snapshot', network: 'host', usb: ['058f:6387']) }
        .to output(%r{USB:\s+/dev/disk5}).to_stdout

      cmd = commands.last
      expect(cmd.first).to eq('sudo')
      expect(cmd).to include('file=/dev/rdisk5,format=raw,if=none,id=usbdisk0')
      expect(cmd).to include('usb-storage,bus=xhci.0,drive=usbdisk0,removable=on')
    end

    it "resolves USB disks before cloning so a missing stick fails fast" do
      allow(Pim::UsbDisk).to receive(:resolve).and_raise(Pim::UsbDisk::Error, "not found")
      expect(Pim::QemuDiskImage).not_to receive(:clone)

      expect { subject.run(disk: 'clone', network: 'host', usb: ['dead:beef']) }
        .to raise_error(Pim::UsbDisk::Error)
    end
  end

  describe "networking" do
    include_context "bootable"

    it "bridged on macOS runs under sudo, bridges the default interface, and adds the guest agent" do
      allow(subject).to receive(:macos?).and_return(true)

      expect { subject.run(disk: 'snapshot', network: 'bridged') }.to output(/bridged \(en0\)/).to_stdout
      expect(subject.ssh_port).to be_nil

      cmd = commands.last
      expect(cmd.first).to eq('sudo')
      expect(cmd.join(' ')).to include('vmnet-bridged,id=net0,ifname=en0')
      expect(cmd.join(' ')).to include('org.qemu.guest_agent.0')
    end

    it "runs QEMU with sudo -n and logs its output" do
      allow(subject).to receive(:macos?).and_return(true)
      expect(vm).to receive(:start_background).with(log_path: '/tmp/pim/dev-debian.log').and_return(vm)

      expect { subject.run(disk: 'snapshot', network: 'bridged') }.to output(%r{QEMU output: /tmp/pim/dev-debian.log}).to_stdout
      expect(commands.last.first(2)).to eq(['sudo', '-n'])
    end

    it "host uses port forwarding without sudo" do
      allow(subject).to receive(:macos?).and_return(true)

      expect { subject.run(disk: 'snapshot', network: 'host') }.to output(/host \(port forwarding\)/).to_stdout
      expect(subject.ssh_port).to eq(2222)
      expect(commands.last.first).not_to eq('sudo')
      expect(commands.last.join(' ')).to include('hostfwd=tcp::2222-:22')
    end
  end

  describe "IP discovery" do
    let(:vm) { instance_double(Pim::QemuVM, running?: true) }

    before do
      subject.instance_variable_set(:@ga_socket, '/tmp/pim/dev-debian.ga')
      subject.instance_variable_set(:@vm, vm)
      allow(subject).to receive(:sleep)
    end

    it "shows progress and returns the first IPv4 address the agent reports" do
      allow(subject).to receive(:query_guest_ip).and_return(nil, nil, '192.168.1.50')

      expect { expect(subject.send(:discover_ip, timeout: 30)).to eq('192.168.1.50') }
        .to output(/Waiting for the VM's IP.*\.\. 192\.168\.1\.50/).to_stdout
    end

    it "gives up without an IP after the timeout" do
      allow(subject).to receive(:query_guest_ip).and_return(nil)

      expect { expect(subject.send(:discover_ip, timeout: 0)).to be_nil }.to output(/no IP yet/).to_stdout
    end

    context "querying the agent socket" do
      let(:dir) { Dir.mktmpdir }
      let(:socket_path) { File.join(dir, 'ga') }
      let(:reply) do
        { 'return' => [
          { 'name' => 'lo', 'ip-addresses' => [{ 'ip-address-type' => 'ipv4', 'ip-address' => '127.0.0.1' }] },
          { 'name' => 'enp0s1', 'ip-addresses' => [{ 'ip-address-type' => 'ipv6', 'ip-address' => 'fe80::1' },
                                                   { 'ip-address-type' => 'ipv4', 'ip-address' => '172.31.16.46' }] }
        ] }
      end

      before do
        subject.instance_variable_set(:@ga_socket, socket_path)
        @server = UNIXServer.new(socket_path)
      end

      after do
        @thread&.kill
        @server.close
        FileUtils.remove_entry(dir)
      end

      it "returns the first non-loopback IPv4 address" do
        @thread = Thread.new do
          client = @server.accept
          client.gets
          client.write("#{JSON.generate(reply)}\n")
          sleep 1
          client.close
        end

        expect(subject.send(:query_guest_ip)).to eq('172.31.16.46')
      end

      it "returns nil instead of hanging when the agent doesn't answer" do
        @thread = Thread.new { client = @server.accept; sleep 10; client.close }

        started = Time.now
        expect(subject.send(:query_guest_ip)).to be_nil
        expect(Time.now - started).to be < 5
      end
    end

    it "takes ownership of the root-owned agent socket only when QEMU runs under sudo" do
      subject.instance_variable_set(:@sudo, true)
      allow(File).to receive(:socket?).with('/tmp/pim/dev-debian.ga').and_return(true)
      expect(subject).to receive(:system)
        .with('sudo', '-n', 'chown', Process.uid.to_s, '/tmp/pim/dev-debian.ga', out: File::NULL, err: File::NULL)
      subject.send(:claim_agent_socket)

      subject.instance_variable_set(:@sudo, false)
      expect(subject).not_to receive(:system)
      subject.send(:claim_agent_socket)
    end

    it "stops with the QEMU log when the VM exits while booting" do
      log = Tempfile.new('qemu-log')
      log.write("qemu-system-aarch64: cannot create vmnet interface\n")
      log.close
      subject.instance_variable_set(:@log_path, log.path)
      allow(vm).to receive(:running?).and_return(false)

      expect { subject.send(:discover_ip, timeout: 30) }
        .to raise_error(Pim::VmRunner::Error, /exited while booting:\nqemu-system-aarch64: cannot create vmnet interface/)
        .and output.to_stdout
    ensure
      log&.unlink
    end
  end

  describe "#find_golden_image" do
    let(:registry) { instance_double(Pim::Registry) }

    before do
      allow(Pim::Registry).to receive(:new).and_return(registry)
    end

    it "raises when no image found" do
      allow(registry).to receive(:find_legacy).and_return(nil)

      expect { subject.run }.to raise_error(Pim::VmRunner::Error, /No image found/)
    end

    it "raises when image file is missing" do
      allow(registry).to receive(:find_legacy).and_return({ 'path' => '/nonexistent.qcow2' })

      expect { subject.run }.to raise_error(Pim::VmRunner::Error, /Image file missing/)
    end
  end

  describe "#stop" do
    it "shuts down the VM" do
      vm = instance_double(Pim::QemuVM)
      allow(vm).to receive(:shutdown)
      subject.instance_variable_set(:@vm, vm)

      subject.stop
      expect(vm).to have_received(:shutdown).with(timeout: 30)
    end
  end

  describe "#running?" do
    it "returns false when no VM" do
      expect(subject.running?).to be false
    end
  end

  describe "#provision" do
    it "raises if VM not running" do
      expect { subject.provision("/tmp/script.sh") }
        .to raise_error(Pim::VmRunner::Error, /not running/)
    end

    it "raises if script doesn't exist" do
      vm = instance_double(Pim::QemuVM, running?: true)
      subject.instance_variable_set(:@vm, vm)

      expect { subject.provision("/nonexistent/script.sh") }
        .to raise_error(Pim::VmRunner::Error, /Script not found/)
    end
  end

  describe "#register_image" do
    it "raises for snapshot mode" do
      subject.instance_variable_set(:@snapshot, true)
      subject.instance_variable_set(:@image_path, "/tmp/test.qcow2")

      expect { subject.register_image(label: "test", script: "/tmp/s.sh") }
        .to raise_error(Pim::VmRunner::Error, /snapshot/)
    end

    it "raises when no image path" do
      subject.instance_variable_set(:@snapshot, false)
      subject.instance_variable_set(:@image_path, nil)

      expect { subject.register_image(label: "test", script: "/tmp/s.sh") }
        .to raise_error(Pim::VmRunner::Error, /no image path/)
    end

    it "calls registry.register_provisioned with correct params" do
      tmp = Dir.mktmpdir
      img_path = File.join(tmp, "dev-debian-20260225-120000.qcow2")
      File.write(img_path, "data")

      subject.instance_variable_set(:@snapshot, false)
      subject.instance_variable_set(:@image_path, img_path)
      subject.instance_variable_set(:@profile, profile)
      subject.instance_variable_set(:@arch, "arm64")

      image_registry = instance_double(Pim::Registry)
      allow(Pim::Registry).to receive(:new).and_return(image_registry)
      allow(image_registry).to receive(:register_provisioned).and_return(
        Pim::Image.new('id' => 'default-arm64-test')
      )

      result = subject.register_image(label: "test", script: "/tmp/setup.sh")
      expect(result.id).to eq("default-arm64-test")
      expect(image_registry).to have_received(:register_provisioned).with(
        parent_id: "default-arm64",
        label: "test",
        path: File.join(tmp, "default-arm64-test.qcow2"),
        script: "/tmp/setup.sh"
      )

      FileUtils.remove_entry(tmp)
    end
  end

  describe "#ssh_target" do
    it "returns localhost + port for host networking" do
      subject.instance_variable_set(:@ssh_port, 2222)
      subject.instance_variable_set(:@bridged, false)

      expect(subject.ssh_target).to eq(['127.0.0.1', 2222])
    end

    it "returns bridge IP + 22 for bridged mode" do
      subject.instance_variable_set(:@bridged, true)
      subject.instance_variable_set(:@bridge_ip, '192.168.1.50')

      expect(subject.ssh_target).to eq(['192.168.1.50', 22])
    end
  end
end
