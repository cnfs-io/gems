# frozen_string_literal: true

RSpec.describe Pim::ProfilesCommand do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:project_dir) { File.join(tmp_dir, "proj") }

  before do
    Pim::New::Scaffold.new(project_dir).create
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

  describe Pim::ProfilesCommand::List do
    it "lists all profiles" do
      output = capture_output { subject.call }
      expect(output).to include("default")
    end

    it "outputs JSON with format option" do
      output = capture_output { subject.call(format: "json") }
      data = JSON.parse(output)
      expect(data).to be_an(Array)
    end
  end

  describe Pim::ProfilesCommand::Show do
    it "shows a profile record by id" do
      output = capture_output { described_class.new.call(id: "default") }
      expect(output).to include("hostname")
    end
  end

  describe Pim::ProfilesCommand::Update do
    let(:profile) { instance_double(Pim::Profile, id: "default") }

    before do
      allow(Pim::Profile).to receive(:find).with("default").and_return(profile)
    end

    it "sets a field directly" do
      expect(profile).to receive(:update).with(hostname: "myhost")
      expect { subject.call(id: "default", field: "hostname", value: "myhost") }
        .to output(/Profile default: hostname = myhost/).to_stdout
    end

    it "exits with error when profile not found" do
      allow(Pim::Profile).to receive(:find).with("missing").and_raise(FlatRecord::RecordNotFound)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(id: "missing") }.to output(/not found/).to_stderr
    end
  end

  it "inherits from RestCli::Command" do
    expect(described_class.superclass).to eq(RestCli::Command)
  end

  it "List inherits from ProfilesCommand" do
    expect(Pim::ProfilesCommand::List.superclass).to eq(Pim::ProfilesCommand)
  end
end
