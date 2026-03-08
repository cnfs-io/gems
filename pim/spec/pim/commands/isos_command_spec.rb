# frozen_string_literal: true

RSpec.describe Pim::IsosCommand do
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

  describe Pim::IsosCommand::List do
    it "lists ISOs (empty catalog)" do
      output = capture_output { subject.call }
      # Empty table or no output when no ISOs
      expect(output).to be_a(String)
    end

    context "with ISOs in catalog" do
      before do
        isos_file = File.join(project_dir, "data", "isos.yml")
        existing = YAML.safe_load_file(isos_file) || []
        existing << {
          "id" => "debian-12",
          "name" => "Debian 12",
          "url" => "https://example.com/debian.iso",
          "architecture" => "amd64"
        }
        File.write(isos_file, YAML.dump(existing))
        Pim.boot!(project_dir: project_dir)
      end

      it "lists all ISOs" do
        output = capture_output { subject.call }
        expect(output).to include("debian-12")
        expect(output).to include("amd64")
      end
    end
  end

  describe Pim::IsosCommand::Show do
    before do
      isos_file = File.join(project_dir, "data", "isos.yml")
      existing = YAML.safe_load_file(isos_file) || []
      existing << {
        "id" => "debian-12",
        "name" => "Debian 12",
        "url" => "https://example.com/debian.iso",
        "architecture" => "amd64"
      }
      File.write(isos_file, YAML.dump(existing))
      Pim.boot!(project_dir: project_dir)
    end

    it "shows an ISO record by id" do
      output = capture_output { described_class.new.call(id: "debian-12") }
      expect(output).to include("Debian 12")
    end
  end

  describe Pim::IsosCommand::Update do
    let(:iso) { instance_double(Pim::Iso, id: "debian-12") }

    before do
      allow(Pim::Iso).to receive(:find).with("debian-12").and_return(iso)
    end

    it "sets a field directly" do
      expect(iso).to receive(:update).with(architecture: "arm64")
      expect { subject.call(id: "debian-12", field: "architecture", value: "arm64") }
        .to output(/ISO debian-12: architecture = arm64/).to_stdout
    end

    it "exits with error when ISO not found" do
      allow(Pim::Iso).to receive(:find).with("missing").and_raise(FlatRecord::RecordNotFound)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(id: "missing") }.to output(/not found/).to_stderr
    end
  end

  it "inherits from RestCli::Command" do
    expect(described_class.superclass).to eq(RestCli::Command)
  end
end
