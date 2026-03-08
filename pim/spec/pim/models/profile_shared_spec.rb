# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Profile shared data loading" do
  let(:shared_dir) { Dir.mktmpdir("provisioning") }
  let(:project_dir) { Dir.mktmpdir("pim-project") }

  before do
    File.write(File.join(shared_dir, "profiles.yml"), YAML.dump([
      { "id" => "default", "hostname" => "shared-host", "username" => "admin", "timezone" => "UTC" },
      { "id" => "dev", "parent_id" => "default", "hostname" => "dev-host" }
    ]))

    FlatRecord.configure do |c|
      c.backend = :yaml
      c.data_paths = [project_dir]
      c.merge_strategy = :deep_merge
      c.id_strategy = :string
    end

    Pim::Profile.data_paths = [shared_dir, project_dir]
  end

  after do
    FileUtils.remove_entry(shared_dir)
    FileUtils.remove_entry(project_dir)
    Pim::Profile.data_paths = nil
  end

  it "loads profiles from shared directory" do
    profiles = Pim::Profile.all
    expect(profiles.map(&:id)).to include("default", "dev")
  end

  it "resolves parent chain from shared profiles" do
    dev = Pim::Profile.find("dev")
    expect(dev.resolved_attributes["hostname"]).to eq("dev-host")
    expect(dev.resolved_attributes["username"]).to eq("admin")
  end

  context "with project-level overrides" do
    before do
      File.write(File.join(project_dir, "profiles.yml"), YAML.dump([
        { "id" => "default", "hostname" => "project-host" }
      ]))
      Pim::Profile.data_paths = [shared_dir, project_dir]
    end

    it "merges project profile over shared profile" do
      profile = Pim::Profile.find("default")
      expect(profile.hostname).to eq("project-host")
      expect(profile.username).to eq("admin")
    end

    it "retains shared-only profiles" do
      expect(Pim::Profile.all.map(&:id)).to include("dev")
    end
  end

  context "with no project profiles" do
    before do
      Pim::Profile.data_paths = [shared_dir]
    end

    it "loads profiles from shared directory only" do
      profiles = Pim::Profile.all
      expect(profiles.map(&:id)).to contain_exactly("default", "dev")
    end
  end

  describe "per-model data_paths" do
    it "supports custom data_paths for shared profiles" do
      shared_dir = Dir.mktmpdir("shared-profiles")
      File.write(File.join(shared_dir, "profiles.yml"), YAML.dump([
        { "id" => "shared", "hostname" => "shared-host" }
      ]))

      Pim::Profile.data_paths = [shared_dir, project_dir]
      profile = Pim::Profile.find("shared")
      expect(profile.hostname).to eq("shared-host")

      FileUtils.remove_entry(shared_dir)
    end
  end
end
