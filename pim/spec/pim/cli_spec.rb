# frozen_string_literal: true

RSpec.describe Pim::CLI do
  def run_cli(*args)
    capture_output do
      begin
        Dry::CLI.new(described_class).call(arguments: args)
      rescue SystemExit
        # dry-cli exits after showing help for prefix commands
      end
    end
  end

  def capture_output
    output = StringIO.new
    $stdout = output
    $stderr = output
    yield
    output.string
  ensure
    $stdout = STDOUT
    $stderr = STDERR
  end

  describe "version" do
    it "prints the version" do
      output = run_cli("version")
      expect(output).to match(/pim \d+\.\d+\.\d+/)
    end
  end

  describe "command registration" do
    it "registers top-level commands" do
      %w[version new serve verify].each do |cmd|
        expect {
          begin
            Dry::CLI.new(described_class).call(arguments: [cmd, "--help"])
          rescue SystemExit
            # dry-cli exits after --help, this is expected
          end
        }.not_to raise_error
      end
    end

    it "registers config subcommands" do
      %w[config].each do |cmd|
        output = run_cli(cmd)
        expect(output).to include("Commands:")
      end
    end

    it "registers profile subcommands" do
      output = run_cli("profile")
      expect(output).to include("Commands:")
    end

    it "registers iso subcommands" do
      output = run_cli("iso")
      expect(output).to include("Commands:")
    end

    it "registers build subcommands" do
      output = run_cli("build")
      expect(output).to include("Commands:")
    end

    it "registers ventoy subcommands" do
      output = run_cli("ventoy")
      expect(output).to include("Commands:")
    end
  end

  describe "aliases" do
    let(:tmp_dir) { Dir.mktmpdir }

    before do
      Pim.reset!
      Pim::New::Scaffold.new(File.join(tmp_dir, "proj")).create
    end

    after do
      Pim.reset!
      FileUtils.remove_entry(tmp_dir)
    end

    it "routes 'config ls' same as 'config list'" do
      Dir.chdir(File.join(tmp_dir, "proj")) do
        Pim.boot!(project_dir: File.join(tmp_dir, "proj"))
        list_output = run_cli("config", "list")
        ls_output = run_cli("config", "ls")
        expect(ls_output).to eq(list_output)
      end
    end
  end

  describe "command structure" do
    it "resource commands inherit from RestCli::Command" do
      [
        Pim::ProfilesCommand,
        Pim::IsosCommand,
        Pim::BuildsCommand,
        Pim::TargetsCommand,
        Pim::VentoyCommand,
        Pim::ConfigCommand
      ].each do |cmd|
        expect(cmd.superclass).to eq(RestCli::Command),
          "Expected #{cmd} to inherit from RestCli::Command"
      end
    end
  end
end
