# frozen_string_literal: true

RSpec.describe Pim::New::Scaffold do
  let(:tmp_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmp_dir) }

  describe "#create" do
    let(:target) { File.join(tmp_dir, "myproject") }
    let(:scaffold) { described_class.new(target) }

    before { scaffold.create }

    it "creates target directory" do
      expect(Dir.exist?(target)).to be true
    end

    it "creates all scaffold subdirectories" do
      described_class::SCAFFOLD_DIRS.each do |dir|
        expect(Dir.exist?(File.join(target, dir))).to be(true), "Expected #{dir}/ to exist"
      end
    end

    it "writes pim.rb as project marker" do
      pim_rb = File.join(target, "pim.rb")
      expect(File.exist?(pim_rb)).to be true
      content = File.read(pim_rb)
      expect(content).to include("Pim.configure")
    end

    it "writes profiles data with default profile" do
      profile_file = File.join(target, "data", "profiles.yml")
      expect(File.exist?(profile_file)).to be true
      data = YAML.safe_load_file(profile_file)
      expect(data).to be_an(Array)
      default = data.find { |p| p["id"] == "default" }
      expect(default).to include("username", "hostname")
    end

    it "writes preseed template in resources/preseeds/default.cfg.erb" do
      preseed_file = File.join(target, "resources", "preseeds", "default.cfg.erb")
      expect(File.exist?(preseed_file)).to be true
      content = File.read(preseed_file)
      expect(content).to include("debian-installer")
    end

    it "writes isos data with Debian ISOs" do
      isos_file = File.join(target, "data", "isos.yml")
      expect(File.exist?(isos_file)).to be true
      data = YAML.safe_load_file(isos_file)
      expect(data).to be_an(Array)
      expect(data.map { |i| i["id"] }).to include("debian-13-amd64", "debian-13-arm64")
    end

    it "writes builds data with default build" do
      builds_file = File.join(target, "data", "builds.yml")
      expect(File.exist?(builds_file)).to be true
      data = YAML.safe_load_file(builds_file)
      expect(data).to be_an(Array)
      default = data.find { |b| b["id"] == "default" }
      expect(default).to include("profile" => "default", "distro" => "debian")
    end

    it "writes targets data with default local target" do
      targets_file = File.join(target, "data", "targets.yml")
      expect(File.exist?(targets_file)).to be true
      data = YAML.safe_load_file(targets_file)
      expect(data).to be_an(Array)
      local = data.find { |t| t["id"] == "local" }
      expect(local["type"]).to eq("local")
    end

    it "writes post_install script in resources/post_installs/default.sh" do
      install_file = File.join(target, "resources", "post_installs", "default.sh")
      expect(File.exist?(install_file)).to be true
      content = File.read(install_file)
      expect(content).to start_with("#!/bin/bash")
    end

    it "writes provisioning scripts in resources/scripts/" do
      expect(File.exist?(File.join(target, "resources", "scripts", "base.sh"))).to be true
      expect(File.exist?(File.join(target, "resources", "scripts", "finalize.sh"))).to be true
    end

    it "writes verification stub in resources/verifications/default.sh" do
      verification_file = File.join(target, "resources", "verifications", "default.sh")
      expect(File.exist?(verification_file)).to be true
      content = File.read(verification_file)
      expect(content).to start_with("#!/bin/bash")
    end

    it "does not write .env file" do
      env_file = File.join(target, ".env")
      expect(File.exist?(env_file)).to be false
    end

    it "generates pim.rb with flat_record config block" do
      content = File.read(File.join(target, "pim.rb"))
      expect(content).to include("config.flat_record")
      expect(content).to include("fr.backend = :yaml")
      expect(content).to include("fr.id_strategy = :string")
    end

    it "generates pim.rb with data_paths documentation" do
      content = File.read(File.join(target, "pim.rb"))
      expect(content).to include("Pim::Profile.data_paths")
      expect(content).to include("../share/profiles")
    end

    it "does not create old individual-layout subdirectories" do
      %w[profiles builds isos targets].each do |subdir|
        expect(Dir.exist?(File.join(target, "data", subdir))).to be(false), "Expected data/#{subdir}/ not to exist"
      end
    end

    it "raises if project already exists" do
      expect { described_class.new(target).create }.to raise_error(/already exists/)
    end
  end
end
