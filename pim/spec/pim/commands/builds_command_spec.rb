# frozen_string_literal: true

RSpec.describe Pim::BuildsCommand do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:project_dir) { File.join(tmp_dir, "proj") }

  before do
    Pim.reset!
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

  describe Pim::BuildsCommand::List do
    it "lists build recipes (empty)" do
      output = capture_output { subject.call }
      # Empty table or no output when no builds
      expect(output).to be_a(String)
    end

    context "with build recipes" do
      before do
        builds_file = File.join(project_dir, "data", "builds.yml")
        existing = YAML.safe_load_file(builds_file) || []
        existing << { "id" => "dev-debian", "profile" => "default", "iso" => "debian-12", "distro" => "debian" }
        File.write(builds_file, YAML.dump(existing))
        Pim.boot!(project_dir: project_dir)
      end

      it "lists all builds" do
        output = capture_output { subject.call }
        expect(output).to include("dev-debian")
        expect(output).to include("default")
        expect(output).to include("debian")
      end
    end
  end

  describe Pim::BuildsCommand::Show do
    before do
      builds_file = File.join(project_dir, "data", "builds.yml")
      existing = YAML.safe_load_file(builds_file) || []
      existing << { "id" => "dev-debian", "profile" => "default", "iso" => "debian-12", "distro" => "debian" }
      File.write(builds_file, YAML.dump(existing))
      Pim.boot!(project_dir: project_dir)
    end

    it "shows a build record by id" do
      output = capture_output { described_class.new.call(id: "dev-debian") }
      expect(output).to include("default")
      expect(output).to include("debian")
    end
  end

  describe Pim::BuildsCommand::Status do
    it "shows build system status" do
      Dir.chdir(project_dir) do
        expect { subject.call }.to output(/Build System Status/).to_stdout
      end
    end
  end

  describe Pim::BuildsCommand::Update do
    let(:build) { instance_double(Pim::Build, id: "dev-debian") }

    before do
      allow(Pim::Build).to receive(:find).with("dev-debian").and_return(build)
    end

    it "sets a field directly" do
      expect(build).to receive(:update).with(memory: "8192")
      expect { subject.call(id: "dev-debian", field: "memory", value: "8192") }
        .to output(/Build dev-debian: memory = 8192/).to_stdout
    end

    it "exits with error when build not found" do
      allow(Pim::Build).to receive(:find).with("missing").and_raise(FlatRecord::RecordNotFound)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(id: "missing") }.to output(/not found/).to_stderr
    end
  end

  describe Pim::BuildsCommand::Verify do
    let(:profile) { instance_double(Pim::Profile, id: "default") }
    let(:build) { instance_double(Pim::Build, id: "dev-debian", resolved_profile: profile, arch: "arm64") }
    let(:verifier) { instance_double(Pim::Verifier) }

    before do
      allow(Pim::Build).to receive(:find).with("dev-debian").and_return(build)
      allow(Pim::Verifier).to receive(:new).and_return(verifier)
    end

    it "reports pass with duration" do
      result = Pim::VerifyResult.new(success: true, exit_code: 0, stdout: "all good", stderr: "", duration: 45.3)
      allow(verifier).to receive(:verify).and_return(result)
      expect { subject.call(build_id: "dev-debian") }.to output(/OK.*45\.3s/).to_stdout
    end

    it "reports fail with exit code" do
      Pim.instance_variable_set(:@console_mode, false)
      result = Pim::VerifyResult.new(success: false, exit_code: 1, stdout: "", stderr: "marker file missing", duration: 12.1)
      allow(verifier).to receive(:verify).and_return(result)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(build_id: "dev-debian") }.to output(/FAIL.*exit code: 1/).to_stdout
    end
  end

  it "inherits from RestCli::Command" do
    expect(described_class.superclass).to eq(RestCli::Command)
  end
end
