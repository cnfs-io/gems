# frozen_string_literal: true

require "tmpdir"

RSpec.describe Pcs::Profile do
  let(:shared_dir) { Dir.mktmpdir("provisioning") }

  before do
    FlatRecord.configure do |c|
      c.backend = :yaml
      c.id_strategy = :integer
    end

    File.write(File.join(shared_dir, "profiles.yml"), YAML.dump([
      {
        "id" => "default",
        "hostname" => "base-host",
        "username" => "admin",
        "password" => "changeme",
        "timezone" => "UTC",
        "locale" => "en_US.UTF-8",
        "packages" => "sudo openssh-server"
      },
      {
        "id" => "pve-node",
        "parent_id" => "default",
        "hostname" => "pve1",
        "interface" => "enp1s0",
        "device" => "/dev/sda"
      }
    ]))

    described_class.data_paths = [shared_dir]
    described_class.store.reload!
  end

  after do
    FileUtils.remove_entry(shared_dir)
    described_class.data_paths = []
  end

  it "does not define SHARED_PROFILES_DIR" do
    expect(described_class.const_defined?(:SHARED_PROFILES_DIR)).to be false
  end

  it "loads profiles from shared directory" do
    expect(described_class.all.map(&:id)).to contain_exactly("default", "pve-node")
  end

  it "resolves parent chain" do
    profile = described_class.find("pve-node")
    expect(profile.resolved_attributes["hostname"]).to eq("pve1")
    expect(profile.resolved_attributes["username"]).to eq("admin")
    expect(profile.resolved_attributes["timezone"]).to eq("UTC")
  end

  it "includes PCS-specific attributes" do
    profile = described_class.find("pve-node")
    expect(profile.interface).to eq("enp1s0")
    expect(profile.device).to eq("/dev/sda")
  end

  it "handles missing PCS-specific attributes gracefully" do
    profile = described_class.find("default")
    expect(profile.interface).to be_nil
    expect(profile.device).to be_nil
  end

  it "respects user-set data_paths" do
    expect(described_class.data_paths.first.to_s).to eq(shared_dir)
  end
end
