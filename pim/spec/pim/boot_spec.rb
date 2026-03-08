# frozen_string_literal: true

RSpec.describe "Pim boot" do
  let(:tmp_dir) { Dir.mktmpdir }

  after do
    Pim.reset!
    FileUtils.remove_entry(tmp_dir)
  end

  describe ".root" do
    it "returns a Pathname" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect(Pim.root(tmp_dir)).to be_a(Pathname)
    end

    it "finds pim.rb in current directory" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect(Pim.root(tmp_dir)).to eq(Pathname(tmp_dir).expand_path)
    end

    it "finds pim.rb in parent directory" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      subdir = File.join(tmp_dir, "sub", "deep")
      FileUtils.mkdir_p(subdir)
      expect(Pim.root(subdir)).to eq(Pathname(tmp_dir).expand_path)
    end

    it "returns nil when no pim.rb exists up the tree" do
      empty_dir = Dir.mktmpdir
      expect(Pim.root(empty_dir)).to be_nil
      FileUtils.remove_entry(empty_dir)
    end
  end

  describe ".root!" do
    it "returns Pathname project root when found" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect(Pim.root!(tmp_dir)).to eq(Pathname(tmp_dir).expand_path)
    end

    it "raises with helpful message when no project found" do
      empty_dir = Dir.mktmpdir
      expect { Pim.root!(empty_dir) }.to raise_error(/No pim.rb found/)
      FileUtils.remove_entry(empty_dir)
    end
  end

  describe ".data_dir" do
    it "returns a Pathname" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect(Pim.data_dir(tmp_dir)).to be_a(Pathname)
    end

    it "returns data/ under project root" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect(Pim.data_dir(tmp_dir)).to eq(Pathname(tmp_dir) / "data")
    end
  end

  describe ".resources_dir" do
    it "returns a Pathname" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect(Pim.resources_dir(tmp_dir)).to be_a(Pathname)
    end

    it "returns resources/ under project root" do
      File.write(File.join(tmp_dir, "pim.rb"), "Pim.configure { |c| }\n")
      expect(Pim.resources_dir(tmp_dir)).to eq(Pathname(tmp_dir) / "resources")
    end
  end

  describe ".boot!" do
    it "configures FlatRecord from nested config block" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "data"))
        File.write(File.join(dir, "pim.rb"), <<~RUBY)
          Pim.configure do |config|
            config.flat_record do |fr|
              fr.backend = :yaml
              fr.id_strategy = :string
            end
          end
        RUBY

        Pim.boot!(project_dir: dir)

        expect(FlatRecord.configuration.backend).to eq(:yaml)
        expect(FlatRecord.configuration.id_strategy).to eq(:string)
        expect(FlatRecord.configuration.data_path).to be_a(Pathname)
      end
    end

    it "does not set multi-path by default" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "data"))
        File.write(File.join(dir, "pim.rb"), "Pim.configure { |c| }\n")
        Pim.boot!(project_dir: dir)

        expect(FlatRecord.configuration.multi_path?).to be false
      end
    end
  end

  describe "full boot cycle from scaffold" do
    it "boots cleanly from a new project scaffold" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "test-project")
        Pim::New::Scaffold.new(target).create
        Pim.boot!(project_dir: target)

        expect(Pim.project_dir).to be_a(Pathname)
        expect(Pim.project_dir.join("pim.rb")).to be_file
        expect(FlatRecord.configuration.backend).to eq(:yaml)
        expect(FlatRecord.configuration.data_path).to be_a(Pathname)
        expect(FlatRecord.configuration.data_path.to_s).to end_with("data")
      end
    end

    it "loads all seeded models from collection files" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "test-project")
        Pim::New::Scaffold.new(target).create
        Pim.boot!(project_dir: target)

        expect(Pim::Profile.all.count).to eq(1)
        expect(Pim::Iso.all.count).to eq(2)
        expect(Pim::Build.all.count).to eq(2)
        expect(Pim::Target.all.count).to eq(1)
        expect(Pim::Build.find("default").resolved_profile.id).to eq("default")
        expect(Pim::Build.find("default").resolved_iso.id).to eq("debian-13-amd64")
      end
    end
  end
end
