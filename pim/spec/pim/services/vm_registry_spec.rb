# frozen_string_literal: true

RSpec.describe Pim::VmRegistry do
  let(:tmp_dir) { Dir.mktmpdir("pim-registry-") }
  let(:state_dir) { File.join(tmp_dir, 'vms') }

  before do
    allow(Pim::Qemu).to receive(:runtime_dir).and_return(tmp_dir)
  end

  after { FileUtils.remove_entry(tmp_dir) }

  subject { described_class.new }

  describe "#register" do
    it "creates a YAML state file in runtime dir" do
      name = subject.register(
        name: "test-vm", pid: Process.pid, build_id: "dev-debian",
        image_path: "/tmp/test.qcow2", ssh_port: 2222
      )

      expect(name).to eq("test-vm")
      path = File.join(state_dir, "test-vm.yml")
      expect(File.exist?(path)).to be true

      state = YAML.safe_load_file(path)
      expect(state['pid']).to eq(Process.pid)
      expect(state['build_id']).to eq("dev-debian")
      expect(state['ssh_port']).to eq(2222)
    end
  end

  describe "#list" do
    it "returns only VMs with alive PIDs" do
      subject.register(
        name: "alive-vm", pid: Process.pid, build_id: "dev",
        image_path: "/tmp/alive.qcow2"
      )

      vms = subject.list
      expect(vms.size).to eq(1)
      expect(vms.first['name']).to eq("alive-vm")
    end

    it "prunes state files for dead PIDs" do
      subject.register(
        name: "dead-vm", pid: 999999999, build_id: "dev",
        image_path: "/tmp/dead.qcow2"
      )

      vms = subject.list
      expect(vms).to be_empty
      expect(File.exist?(File.join(state_dir, "dead-vm.yml"))).to be false
    end
  end

  describe "#find" do
    before do
      subject.register(
        name: "first-vm", pid: Process.pid, build_id: "dev",
        image_path: "/tmp/first.qcow2"
      )
    end

    it "finds by numeric index (1-based)" do
      vm = subject.find("1")
      expect(vm['name']).to eq("first-vm")
    end

    it "finds by name" do
      vm = subject.find("first-vm")
      expect(vm['name']).to eq("first-vm")
    end

    it "returns nil for unknown identifier" do
      expect(subject.find("99")).to be_nil
      expect(subject.find("nonexistent")).to be_nil
    end
  end

  describe "#unique_name" do
    it "appends counter for duplicate names" do
      subject.register(
        name: "my-vm", pid: Process.pid, build_id: "dev",
        image_path: "/tmp/a.qcow2"
      )

      name2 = subject.register(
        name: "my-vm", pid: Process.pid, build_id: "dev",
        image_path: "/tmp/b.qcow2"
      )

      expect(name2).to eq("my-vm-2")
    end
  end

  describe "#unregister" do
    it "removes state file" do
      subject.register(
        name: "remove-me", pid: Process.pid, build_id: "dev",
        image_path: "/tmp/rm.qcow2"
      )

      subject.unregister("remove-me")
      expect(File.exist?(File.join(state_dir, "remove-me.yml"))).to be false
    end
  end

  describe "#update" do
    it "updates fields in state file" do
      subject.register(
        name: "update-vm", pid: Process.pid, build_id: "dev",
        image_path: "/tmp/up.qcow2"
      )

      subject.update("update-vm", bridge_ip: "192.168.1.100")

      state = YAML.safe_load_file(File.join(state_dir, "update-vm.yml"))
      expect(state['bridge_ip']).to eq("192.168.1.100")
    end
  end
end
