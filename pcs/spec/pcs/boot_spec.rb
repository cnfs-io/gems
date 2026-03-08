# frozen_string_literal: true

RSpec.describe "Pcs.root" do
  it "returns a Pathname when pcs.rb found" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "pcs.rb"), "Pcs.configure { |c| }")
      result = Pcs.root(dir)
      expect(result).to be_a(Pathname)
      expect(result.to_s).to eq(Pathname(dir).expand_path.to_s)
    end
  end

  it "returns nil when no pcs.rb found" do
    Dir.mktmpdir do |dir|
      expect(Pcs.root(dir)).to be_nil
    end
  end

  it "finds root from a subdirectory" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "pcs.rb"), "Pcs.configure { |c| }")
      subdir = File.join(dir, "sites", "sg")
      FileUtils.mkdir_p(subdir)
      result = Pcs.root(subdir)
      expect(result.to_s).to eq(Pathname(dir).expand_path.to_s)
    end
  end
end

RSpec.describe "Pcs.root!" do
  it "raises ProjectNotFoundError when no pcs.rb found" do
    Dir.mktmpdir do |dir|
      expect { Pcs.root!(dir) }.to raise_error(Pcs::ProjectNotFoundError)
    end
  end
end

RSpec.describe "Pcs.boot!", :uses_fixture_project do
  it "sets project_dir" do
    expect(Pcs.project_dir).to be_a(Pathname)
    expect(Pcs.project_dir.realpath.to_s).to eq(Pathname.pwd.realpath.to_s)
  end

  it "configures FlatRecord from nested config block" do
    expect(FlatRecord.configuration.backend).to eq(:yaml)
    expect(FlatRecord.configuration.data_path).to be_a(Pathname)
  end

  it "loads config DSL from pcs.rb" do
    expect(Pcs.config).to be_a(Pcs::Config)
    expect(Pcs.config.networking.dns_fallback_resolvers).to eq(["1.1.1.1", "8.8.8.8"])
  end

  it "resolves site from .env" do
    expect(Pcs.site).to eq("sg")
  end
end

RSpec.describe "Pcs.site_dir", :uses_fixture_project do
  it "returns correct path for a given site name" do
    expected = Pcs.project_dir / "sites" / "rok"
    expect(Pcs.site_dir("rok")).to eq(expected)
  end
end

RSpec.describe Pcs::Config do
  it "has flat_record nested config" do
    config = Pcs::Config.new
    config.flat_record do |fr|
      fr.backend = :json
      fr.hierarchy model: :site, key: :name
    end
    expect(config.flat_record.backend).to eq(:json)
    expect(config.flat_record.hierarchy_model).to eq(:site)
    expect(config.flat_record.hierarchy_key).to eq(:name)
  end
end
