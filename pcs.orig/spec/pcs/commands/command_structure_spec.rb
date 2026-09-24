# frozen_string_literal: true

RSpec.describe "command structure" do
  {
    Pcs::HostsCommand => RestCli::Command,
    Pcs::ServicesCommand => RestCli::Command,
    Pcs::SitesCommand => RestCli::Command,
    Pcs::ClustersCommand => RestCli::Command,
    Pcs::CpCommand => RestCli::Command
  }.each do |klass, parent|
    it "#{klass} inherits from #{parent}" do
      expect(klass.superclass).to eq(parent)
    end
  end

  {
    Pcs::HostsCommand::List => Pcs::HostsCommand,
    Pcs::HostsCommand::Show => Pcs::HostsCommand,
    Pcs::HostsCommand::Add => Pcs::HostsCommand,
    Pcs::HostsCommand::Update => Pcs::HostsCommand,
    Pcs::HostsCommand::Remove => Pcs::HostsCommand,
    Pcs::NetworksCommand::List => Pcs::NetworksCommand,
    Pcs::NetworksCommand::Show => Pcs::NetworksCommand,
    Pcs::NetworksCommand::Add => Pcs::NetworksCommand,
    Pcs::NetworksCommand::Update => Pcs::NetworksCommand,
    Pcs::NetworksCommand::Remove => Pcs::NetworksCommand,
    Pcs::NetworksCommand::Scan => Pcs::NetworksCommand,
    Pcs::ServicesCommand::List => Pcs::ServicesCommand,
    Pcs::ServicesCommand::Start => Pcs::ServicesCommand,
    Pcs::SitesCommand::List => Pcs::SitesCommand,
    Pcs::SitesCommand::Add => Pcs::SitesCommand,
    Pcs::ClustersCommand::Install => Pcs::ClustersCommand,
    Pcs::CpCommand::Setup => Pcs::CpCommand
  }.each do |klass, parent|
    it "#{klass} inherits from #{parent}" do
      expect(klass.superclass).to eq(parent)
    end
  end
end

RSpec.describe "model namespace" do
  %w[Host Site Config State Profile Network Interface].each do |name|
    it "#{name} is at Pcs::#{name}" do
      expect(Pcs.const_defined?(name)).to be true
      expect(Pcs.const_get(name)).to be_a(Class)
    end
  end

  it "Pcs::ProjectConfig is not defined" do
    expect(defined?(Pcs::ProjectConfig)).to be_nil
  end

  it "Pcs::Models is not defined" do
    expect(defined?(Pcs::Models)).to be_nil
  end
end

RSpec.describe "Host STI" do
  it "Pcs::PveHost is a subclass of Pcs::Host" do
    expect(Pcs::PveHost.superclass).to eq(Pcs::Host)
  end

  it "Pcs::TruenasHost is a subclass of Pcs::Host" do
    expect(Pcs::TruenasHost.superclass).to eq(Pcs::Host)
  end

  it "Pcs::PikvmHost is a subclass of Pcs::Host" do
    expect(Pcs::PikvmHost.superclass).to eq(Pcs::Host)
  end

  it "Pcs::RpiHost is a subclass of Pcs::Host" do
    expect(Pcs::RpiHost.superclass).to eq(Pcs::Host)
  end
end

RSpec.describe "no old references in lib" do
  Dir.glob("lib/**/*.rb").each do |file|
    it "#{file} does not reference Models::" do
      content = File.read(file)
      expect(content).not_to match(/Models::(Device|Service|Site|Config|State)/),
        "#{file} still references Models:: namespace"
    end

    it "#{file} does not reference Pcs::Hosts::" do
      content = File.read(file)
      expect(content).not_to match(/Pcs::Hosts::/),
        "#{file} still references old Pcs::Hosts:: namespace"
    end

    it "#{file} does not reference Pcs::Device" do
      content = File.read(file)
      expect(content).not_to match(/\bPcs::Device\b/),
        "#{file} still references Pcs::Device"
    end

    it "#{file} does not reference site.get(" do
      content = File.read(file)
      expect(content).not_to match(/site\.get\(/),
        "#{file} still uses site.get() instead of direct accessors"
    end
  end
end

RSpec.describe "simplification tier cleanup" do
  Dir.glob("lib/**/*.rb").each do |file|
    it "#{file} does not reference Pcs::Project." do
      content = File.read(file)
      expect(content).not_to match(/Pcs::Project\./),
        "#{file} still references Pcs::Project"
    end

    it "#{file} does not reference FlatRecordConfig" do
      content = File.read(file)
      expect(content).not_to match(/FlatRecordConfig/),
        "#{file} still references FlatRecordConfig"
    end

    it "#{file} does not reference AutoConfigStore" do
      content = File.read(file)
      expect(content).not_to match(/AutoConfigStore/),
        "#{file} still references AutoConfigStore"
    end
  end

  it "lib/pcs/project.rb does not exist" do
    expect(File.exist?("lib/pcs/project.rb")).to be false
  end

  it "lib/pcs/flat_record_config.rb does not exist" do
    expect(File.exist?("lib/pcs/flat_record_config.rb")).to be false
  end

  Dir.glob("lib/**/*.rb").each do |file|
    it "#{file} does not reference ProjectConfig" do
      content = File.read(file)
      expect(content).not_to match(/ProjectConfig/),
        "#{file} still references ProjectConfig"
    end

    it "#{file} does not reference project_config" do
      content = File.read(file)
      expect(content).not_to match(/project_config/),
        "#{file} still references project_config"
    end
  end
end

RSpec.describe "old files removed" do
  it "lib/pcs/concern/ directory does not exist" do
    expect(Dir.exist?("lib/pcs/concern")).to be false
  end

  it "lib/pcs/hosts/ directory does not exist" do
    expect(Dir.exist?("lib/pcs/hosts")).to be false
  end

  it "lib/pcs/models/device.rb does not exist" do
    expect(File.exist?("lib/pcs/models/device.rb")).to be false
  end

  it "lib/pcs/commands/devices_command.rb does not exist" do
    expect(File.exist?("lib/pcs/commands/devices_command.rb")).to be false
  end

  it "lib/pcs/views/devices_view.rb does not exist" do
    expect(File.exist?("lib/pcs/views/devices_view.rb")).to be false
  end
end
