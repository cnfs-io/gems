# frozen_string_literal: true

RSpec.describe Pim::Profile do
  describe "scaffold defaults" do
    let!(:project_dir) { TestProject.create_and_boot }

    after { TestProject.cleanup(project_dir) }

    it "returns all profiles from YAML" do
      profiles = described_class.all
      expect(profiles.map(&:id)).to include("default")
    end

    it "returns profile by id" do
      profile = described_class.find("default")
      expect(profile.hostname).to eq("debian")
      expect(profile.username).to eq("ansible")
    end

    it "raises RecordNotFound for unknown id" do
      expect { described_class.find("nonexistent") }.to raise_error(FlatRecord::RecordNotFound)
    end

    it "#name returns the id" do
      expect(described_class.find("default").name).to eq("default")
    end

    it "#to_h returns compact attributes hash" do
      h = described_class.find("default").to_h
      expect(h).to include("hostname" => "debian", "username" => "ansible")
      expect(h.values).not_to include(nil)
    end

    it "#[] accesses attribute by string key" do
      expect(described_class.find("default")["hostname"]).to eq("debian")
    end

    it "#[] accesses attribute by symbol key" do
      expect(described_class.find("default")[:hostname]).to eq("debian")
    end

    it "#[] returns nil for unknown attribute" do
      expect(described_class.find("default")["nonexistent"]).to be_nil
    end
  end

  describe "empty state" do
    let(:tmp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmp_dir) }

    it "returns empty array when no profiles.yml exists" do
      FlatRecord.configure do |c|
        c.backend = :yaml
        c.data_paths = [tmp_dir]
        c.merge_strategy = :deep_merge
        c.id_strategy = :string
      end
      Pim::Profile.data_paths = nil
      Pim::Profile.reload!

      expect(described_class.all).to eq([])
    end
  end

  describe "deep merge across paths" do
    let(:tmp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmp_dir) }

    it "merges project values over global defaults" do
      global_dir = File.join(tmp_dir, "global")
      project_dir = File.join(tmp_dir, "project")
      FileUtils.mkdir_p([global_dir, project_dir])

      File.write(File.join(global_dir, "profiles.yml"), YAML.dump([
        { "id" => "default", "hostname" => "global-host", "username" => "globaluser", "timezone" => "UTC" }
      ]))
      File.write(File.join(project_dir, "profiles.yml"), YAML.dump([
        { "id" => "default", "hostname" => "project-host" }
      ]))

      FlatRecord.configure do |c|
        c.backend = :yaml
        c.data_paths = [global_dir, project_dir]
        c.merge_strategy = :deep_merge
        c.id_strategy = :string
      end
      Pim::Profile.data_paths = nil
      Pim::Profile.reload!
      Pim::Iso.reload!

      profile = described_class.find("default")
      expect(profile.hostname).to eq("project-host")
      expect(profile.username).to eq("globaluser")
      expect(profile.timezone).to eq("UTC")
    end
  end

  describe "template resolution" do
    let!(:project_dir) { TestProject.create_and_boot }

    after { TestProject.cleanup(project_dir) }

    before do
      TestProject.append_records(project_dir, "profiles", [
        { "id" => "developer", "parent_id" => "default", "hostname" => "dev" }
      ])
      TestProject.boot(project_dir)
    end

    describe "#preseed_template" do
      it "finds preseed template by profile name" do
        preseeds_dir = File.join(project_dir, "resources", "preseeds")
        template_path = File.join(preseeds_dir, "developer.cfg.erb")
        File.write(template_path, "preseed content")

        profile = described_class.find("developer")
        expect(profile.preseed_template).to eq(template_path)
      end

      it "falls back to default preseed template" do
        profile = described_class.find("developer")
        default_path = File.join(project_dir, "resources", "preseeds", "default.cfg.erb")
        expect(profile.preseed_template).to eq(default_path)
      end

      it "returns falsey when no preseed template exists" do
        # Remove the default preseed
        FileUtils.rm_f(File.join(project_dir, "resources", "preseeds", "default.cfg.erb"))
        profile = described_class.find("developer")
        expect(profile.preseed_template).to be_falsey
      end

      it "does not fall back to default when profile is default" do
        FileUtils.rm_f(File.join(project_dir, "resources", "preseeds", "default.cfg.erb"))
        profile = described_class.find("default")
        expect(profile.preseed_template).to be_falsey
      end
    end

    describe "#install_template" do
      it "finds install template by profile name" do
        installs_dir = File.join(project_dir, "resources", "post_installs")
        template_path = File.join(installs_dir, "developer.sh")
        File.write(template_path, "#!/bin/bash")

        profile = described_class.find("developer")
        expect(profile.install_template).to eq(template_path)
      end

      it "falls back to default install template" do
        profile = described_class.find("developer")
        default_path = File.join(project_dir, "resources", "post_installs", "default.sh")
        expect(profile.install_template).to eq(default_path)
      end

      it "returns nil when no install template exists" do
        FileUtils.rm_f(File.join(project_dir, "resources", "post_installs", "default.sh"))
        profile = described_class.find("developer")
        expect(profile.install_template).to be_nil
      end
    end

    describe "#verification_script" do
      it "finds verification script by profile name" do
        verifications_dir = File.join(project_dir, "resources", "verifications")
        script_path = File.join(verifications_dir, "developer.sh")
        File.write(script_path, "#!/bin/bash")

        profile = described_class.find("developer")
        expect(profile.verification_script).to eq(script_path)
      end

      it "falls back to default verification script" do
        profile = described_class.find("developer")
        default_path = File.join(project_dir, "resources", "verifications", "default.sh")
        expect(profile.verification_script).to eq(default_path)
      end
    end
  end

  describe "parent_id inheritance" do
    let!(:project_dir) { TestProject.create }

    after { TestProject.cleanup(project_dir) }

    before do
      TestProject.write_records(project_dir, "profiles", [
        { "id" => "default", "hostname" => "debian", "username" => "ansible", "timezone" => "UTC", "packages" => "curl sudo" },
        { "id" => "dev", "parent_id" => "default", "packages" => "curl sudo vim git" },
        { "id" => "dev-roberto", "parent_id" => "dev", "authorized_keys_url" => "https://github.com/rjayroach.keys", "timezone" => "Asia/Singapore" }
      ])
      TestProject.boot(project_dir)
    end

    describe "#parent" do
      it "returns the parent profile" do
        dev = described_class.find("dev")
        expect(dev.parent.id).to eq("default")
      end

      it "returns nil when no parent_id" do
        default = described_class.find("default")
        expect(default.parent).to be_nil
      end
    end

    describe "#parent_chain" do
      it "returns [self] when no parent" do
        default = described_class.find("default")
        expect(default.parent_chain.map(&:id)).to eq(["default"])
      end

      it "returns chain from root to self" do
        roberto = described_class.find("dev-roberto")
        expect(roberto.parent_chain.map(&:id)).to eq(["default", "dev", "dev-roberto"])
      end

      it "raises on circular reference" do
        TestProject.write_records(project_dir, "profiles", [
          { "id" => "a", "parent_id" => "b" },
          { "id" => "b", "parent_id" => "a" }
        ])
        TestProject.boot(project_dir)

        expect { described_class.find("a").parent_chain }.to raise_error(/Circular parent_id/)
      end
    end

    describe "#resolved_attributes" do
      it "merges parent attributes" do
        dev = described_class.find("dev")
        resolved = dev.resolved_attributes
        expect(resolved["hostname"]).to eq("debian")
        expect(resolved["username"]).to eq("ansible")
        expect(resolved["packages"]).to eq("curl sudo vim git")
      end

      it "child fields override parent" do
        roberto = described_class.find("dev-roberto")
        resolved = roberto.resolved_attributes
        expect(resolved["timezone"]).to eq("Asia/Singapore")
      end

      it "preserves grandparent -> parent -> child merge order" do
        roberto = described_class.find("dev-roberto")
        resolved = roberto.resolved_attributes
        expect(resolved["hostname"]).to eq("debian")
        expect(resolved["packages"]).to eq("curl sudo vim git")
        expect(resolved["authorized_keys_url"]).to eq("https://github.com/rjayroach.keys")
        expect(resolved["timezone"]).to eq("Asia/Singapore")
      end

      it "includes id of self, not parent" do
        dev = described_class.find("dev")
        expect(dev.resolved_attributes["id"]).to eq("dev")
      end

      it "preserves fields only on parent" do
        dev = described_class.find("dev")
        expect(dev.resolved_attributes["username"]).to eq("ansible")
      end
    end

    describe "#to_h" do
      it "returns resolved attributes" do
        dev = described_class.find("dev")
        h = dev.to_h
        expect(h["hostname"]).to eq("debian")
        expect(h["username"]).to eq("ansible")
        expect(h["packages"]).to eq("curl sudo vim git")
      end
    end

    describe "#raw_to_h" do
      it "returns only directly-set attributes" do
        dev = described_class.find("dev")
        raw = dev.raw_to_h
        expect(raw).to include("parent_id" => "default", "packages" => "curl sudo vim git")
        expect(raw).not_to have_key("hostname")
        expect(raw).not_to have_key("username")
      end
    end

    describe "#resolve" do
      it "walks parent chain for specific field" do
        roberto = described_class.find("dev-roberto")
        expect(roberto.resolve("hostname")).to eq("debian")
        expect(roberto.resolve("timezone")).to eq("Asia/Singapore")
      end
    end
  end
end
