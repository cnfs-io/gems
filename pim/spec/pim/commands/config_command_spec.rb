# frozen_string_literal: true

RSpec.describe Pim::ConfigCommand do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:project_dir) { File.join(tmp_dir, "proj") }

  before do
    Pim.reset!
    Pim::New::Scaffold.new(project_dir).create
    Pim.configure do |c|
      c.serve_port = 9090
    end
  end

  after do
    Pim.reset!
    FileUtils.remove_entry(tmp_dir)
  end

  describe Pim::ConfigCommand::List do
    it "lists configuration key-value pairs" do
      Dir.chdir(project_dir) do
        expect { subject.call }.to output(/serve_port=9090/).to_stdout
      end
    end
  end

  describe Pim::ConfigCommand::Get do
    it "gets a specific config value" do
      Dir.chdir(project_dir) do
        expect { subject.call(key: "serve_port") }.to output(/9090/).to_stdout
      end
    end

    it "exits with error for missing key" do
      Pim.instance_variable_set(:@console_mode, false)
      Dir.chdir(project_dir) do
        expect(Kernel).to receive(:exit).with(1)
        expect { subject.call(key: "nonexistent") }.to output(/not found/).to_stderr
      end
    end
  end

  describe Pim::ConfigCommand::Set do
    it "advises to edit pim.rb" do
      Dir.chdir(project_dir) do
        expect { subject.call(key: "serve_port", value: "9090") }.to output(/pim\.rb/).to_stdout
      end
    end
  end

  it "inherits from RestCli::Command" do
    expect(described_class.superclass).to eq(RestCli::Command)
  end
end
