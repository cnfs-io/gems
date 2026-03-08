# frozen_string_literal: true

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

  describe "#prepare_image (via run)" do
    let(:golden_image) { "/tmp/images/default-arm64.qcow2" }
    let(:registry) { instance_double(Pim::Registry) }
    let(:entry) { { 'path' => golden_image } }

    before do
      allow(Pim::Registry).to receive(:new).and_return(registry)
      allow(registry).to receive(:find_legacy).and_return(entry)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(golden_image).and_return(true)
      allow(Pim::Qemu).to receive(:find_available_port).and_return(2222)
      allow(Pim::Qemu).to receive(:find_efi_firmware).and_return(nil)
    end

    it "with snapshot: true returns the golden image path unchanged" do
      vm = instance_double(Pim::QemuVM, pid: 123, running?: true)
      allow(Pim::QemuVM).to receive(:new).and_return(vm)
      allow(vm).to receive(:start_background).and_return(vm)

      expect { subject.run(snapshot: true) }.to output(/VM:/).to_stdout
      expect(subject.image_path).to eq(golden_image)
    end

    it "with snapshot: false calls QemuDiskImage.create_overlay" do
      vm_dir = File.join(Pim.data_home, 'vms')
      allow(FileUtils).to receive(:mkdir_p)
      expect(Pim::QemuDiskImage).to receive(:create_overlay)
        .with(golden_image, anything)
        .and_return(Pim::QemuDiskImage.allocate)

      vm = instance_double(Pim::QemuVM, pid: 123, running?: true)
      allow(Pim::QemuVM).to receive(:new).and_return(vm)
      allow(vm).to receive(:start_background).and_return(vm)

      expect { subject.run(snapshot: false) }.to output(/VM:/).to_stdout
    end

    it "with clone: true calls QemuDiskImage.clone" do
      allow(FileUtils).to receive(:mkdir_p)
      expect(Pim::QemuDiskImage).to receive(:clone)
        .with(golden_image, anything)
        .and_return(Pim::QemuDiskImage.allocate)

      vm = instance_double(Pim::QemuVM, pid: 123, running?: true)
      allow(Pim::QemuVM).to receive(:new).and_return(vm)
      allow(vm).to receive(:start_background).and_return(vm)

      expect { subject.run(snapshot: false, clone: true) }.to output(/Cloning/).to_stdout
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

  describe "bridged networking" do
    let(:golden_image) { "/tmp/images/default-arm64.qcow2" }
    let(:registry) { instance_double(Pim::Registry) }
    let(:entry) { { 'path' => golden_image } }

    before do
      allow(Pim::Registry).to receive(:new).and_return(registry)
      allow(registry).to receive(:find_legacy).and_return(entry)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(golden_image).and_return(true)
      allow(Pim::Qemu).to receive(:find_efi_firmware).and_return(nil)
      allow(Pim::Qemu).to receive(:runtime_dir).and_return('/tmp/pim')
    end

    it "with bridged: true does not set ssh_port" do
      vm = instance_double(Pim::QemuVM, pid: 123, running?: true)
      allow(Pim::QemuVM).to receive(:new).and_return(vm)
      allow(vm).to receive(:start_background).and_return(vm)
      allow(subject).to receive(:discover_ip).and_return(nil)

      expect { subject.run(bridged: true) }.to output(/bridged/).to_stdout
      expect(subject.ssh_port).to be_nil
    end

    it "adds guest agent channel for bridged mode" do
      vm = instance_double(Pim::QemuVM, pid: 123, running?: true)
      allow(Pim::QemuVM).to receive(:new).and_return(vm)
      allow(vm).to receive(:start_background).and_return(vm)
      allow(subject).to receive(:discover_ip).and_return(nil)

      expect(Pim::QemuVM).to receive(:new) do |args|
        cmd = args[:command]
        expect(cmd.join(' ')).to include('virtio-serial-pci')
        expect(cmd.join(' ')).to include('org.qemu.guest_agent.0')
        vm
      end

      expect { subject.run(bridged: true) }.to output(/VM:/).to_stdout
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
    it "returns localhost + port for user-mode" do
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
