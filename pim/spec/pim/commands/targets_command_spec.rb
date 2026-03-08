# frozen_string_literal: true

RSpec.describe Pim::TargetsCommand do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:project_dir) { File.join(tmp_dir, "proj") }

  before do
    Pim::New::Scaffold.new(project_dir).create
    targets_file = File.join(project_dir, "data", "targets.yml")
    existing = YAML.safe_load_file(targets_file) || []
    existing << { "id" => "proxmox-sg", "type" => "proxmox", "host" => "192.168.1.100", "node" => "pve1" }
    File.write(targets_file, YAML.dump(existing))
    Pim.boot!(project_dir: project_dir)
  end

  after { FileUtils.remove_entry(tmp_dir) }

  def capture_output
    stdout = StringIO.new
    $stdout = stdout
    yield
    stdout.string
  ensure
    $stdout = STDOUT
  end

  describe Pim::TargetsCommand::List do
    it "lists all targets" do
      output = capture_output { subject.call }
      expect(output).to include("local")
      expect(output).to include("proxmox-sg")
    end

    it "shows empty table when no targets exist" do
      File.write(File.join(project_dir, "data", "targets.yml"), YAML.dump([]))
      Pim.boot!(project_dir: project_dir)
      output = capture_output { subject.call }
      expect(output).to be_a(String)
    end
  end

  describe Pim::TargetsCommand::Show do
    it "shows a target record by id" do
      output = capture_output { described_class.new.call(id: "proxmox-sg") }
      expect(output).to include("proxmox-sg")
      expect(output).to include("proxmox")
    end
  end

  describe Pim::TargetsCommand::Update do
    let(:target) { instance_double(Pim::Target, id: "proxmox-sg") }

    before do
      allow(Pim::Target).to receive(:find).with("proxmox-sg").and_return(target)
    end

    it "sets a field directly" do
      expect(target).to receive(:update).with(name: "new-name")
      expect { subject.call(id: "proxmox-sg", field: "name", value: "new-name") }
        .to output(/Target proxmox-sg: name = new-name/).to_stdout
    end

    it "exits with error when target not found" do
      allow(Pim::Target).to receive(:find).with("missing").and_raise(FlatRecord::RecordNotFound)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(id: "missing") }.to output(/not found/).to_stderr
    end
  end

  it "inherits from RestCli::Command" do
    expect(described_class.superclass).to eq(RestCli::Command)
  end
end
