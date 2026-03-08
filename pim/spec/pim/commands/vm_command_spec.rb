# frozen_string_literal: true

require 'tempfile'

RSpec.describe Pim::VmCommand do
  it "inherits from RestCli::Command" do
    expect(described_class.superclass).to eq(RestCli::Command)
  end

  describe Pim::VmCommand::Run do
    let(:profile) { instance_double(Pim::Profile, id: "default") }
    let(:build) do
      instance_double(Pim::Build,
                      id: "dev-debian",
                      resolved_profile: profile,
                      arch: "arm64",
                      memory: 2048,
                      cpus: 2,
                      ssh_user: "ansible")
    end
    let(:runner) { instance_double(Pim::VmRunner) }
    let(:vm) { instance_double(Pim::QemuVM, pid: 123) }

    before do
      allow(Pim::Build).to receive(:find).with("dev-debian").and_return(build)
      allow(Pim::VmRunner).to receive(:new).and_return(runner)
      allow(runner).to receive(:run).and_return(runner)
      allow(runner).to receive(:vm).and_return(vm)
      allow(runner).to receive(:instance_name).and_return("dev-debian")
    end

    it "is registered at 'vm run'" do
      expect {
        begin
          Dry::CLI.new(Pim::CLI).call(arguments: ["vm", "run", "--help"])
        rescue SystemExit
          # expected for --help
        end
      }.not_to raise_error
    end

    it "boots a VM from a build" do
      expect(runner).to receive(:run).with(
        snapshot: true,
        clone: false,
        console: false,
        memory: nil,
        cpus: nil,
        bridged: false,
        bridge: nil
      )

      expect { subject.call(build_id: "dev-debian") }.to output(/VM is running/).to_stdout
    end

    it "--clone implies snapshot: false" do
      expect(runner).to receive(:run).with(
        snapshot: false,
        clone: true,
        console: false,
        memory: nil,
        cpus: nil,
        bridged: false,
        bridge: nil
      )

      expect { subject.call(build_id: "dev-debian", clone: true) }.to output(/VM is running/).to_stdout
    end

    it "exits with error for missing build" do
      allow(Pim::Build).to receive(:find).with("missing").and_raise(FlatRecord::RecordNotFound)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(build_id: "missing") }.to output(/not found/).to_stderr
    end

    it "--run and --run-and-stay are mutually exclusive" do
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect {
        subject.call(build_id: "dev-debian", run: "a.sh", run_and_stay: "b.sh")
      }.to output(/Cannot use both/).to_stderr
    end

    it "--run with nonexistent script prints error" do
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect {
        subject.call(build_id: "dev-debian", run: "/nonexistent/script.sh")
      }.to output(/Script not found/).to_stderr
    end

    it "--run implies snapshot: false" do
      script = Tempfile.new(['provision', '.sh'])
      script.write("#!/bin/bash\necho hello")
      script.close

      image = Pim::Image.new('id' => 'default-arm64-test', 'status' => 'provisioned')
      allow(runner).to receive(:provision).and_return({ exit_code: 0, stdout: '', stderr: '' })
      allow(runner).to receive(:register_image).and_return(image)
      allow(runner).to receive(:stop)

      expect(runner).to receive(:run).with(
        hash_including(snapshot: false)
      ).and_return(runner)

      expect {
        subject.call(build_id: "dev-debian", run: script.path, label: "test")
      }.to output(/--run implies --no-snapshot/).to_stdout

      script.unlink
    end

    it "--run without --label errors when require_label is true" do
      Pim.configure { |c| c.images { |i| i.require_label = true } }
      script = Tempfile.new(['provision', '.sh'])
      script.write("#!/bin/bash\necho hello")
      script.close

      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect {
        subject.call(build_id: "dev-debian", run: script.path)
      }.to output(/--run requires --label/).to_stderr

      script.unlink
    end

    it "--run without --label auto-generates label when require_label is false" do
      Pim.configure { |c| c.images { |i| i.require_label = false } }
      script = Tempfile.new(['setup-k8s-node', '.sh'])
      script.write("#!/bin/bash\necho hello")
      script.close

      image = Pim::Image.new('id' => 'default-arm64-setup-k8s-node', 'status' => 'provisioned')
      allow(runner).to receive(:provision).and_return({ exit_code: 0, stdout: '', stderr: '' })
      allow(runner).to receive(:register_image).and_return(image)
      allow(runner).to receive(:stop)
      allow(runner).to receive(:run).and_return(runner)

      expect {
        subject.call(build_id: "dev-debian", run: script.path)
      }.to output(/Image registered/).to_stdout

      script.unlink
    end

    it "--label validates format" do
      script = Tempfile.new(['provision', '.sh'])
      script.write("#!/bin/bash\necho hello")
      script.close

      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect {
        subject.call(build_id: "dev-debian", run: script.path, label: "Invalid Label!")
      }.to output(/Invalid label/).to_stderr

      script.unlink
    end
  end

  describe Pim::VmCommand::List do
    it "is registered at 'vm list'" do
      expect {
        begin
          Dry::CLI.new(Pim::CLI).call(arguments: ["vm", "list", "--help"])
        rescue SystemExit; end
      }.not_to raise_error
    end

    it "shows no running VMs when empty" do
      registry = instance_double(Pim::VmRegistry)
      allow(Pim::VmRegistry).to receive(:new).and_return(registry)
      allow(registry).to receive(:list).and_return([])

      expect { subject.call }.to output(/No running VMs/).to_stdout
    end
  end

  describe Pim::VmCommand::Stop do
    it "is registered at 'vm stop'" do
      expect {
        begin
          Dry::CLI.new(Pim::CLI).call(arguments: ["vm", "stop", "--help"])
        rescue SystemExit; end
      }.not_to raise_error
    end

    it "exits with error for unknown identifier" do
      registry = instance_double(Pim::VmRegistry)
      allow(Pim::VmRegistry).to receive(:new).and_return(registry)
      allow(registry).to receive(:find).and_return(nil)

      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(identifier: "99") }.to output(/not found/).to_stderr
    end
  end

  describe Pim::VmCommand::Ssh do
    it "is registered at 'vm ssh'" do
      expect {
        begin
          Dry::CLI.new(Pim::CLI).call(arguments: ["vm", "ssh", "--help"])
        rescue SystemExit; end
      }.not_to raise_error
    end
  end
end
