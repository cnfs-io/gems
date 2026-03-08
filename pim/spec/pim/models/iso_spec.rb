# frozen_string_literal: true

RSpec.describe Pim::Iso do
  describe "scaffold defaults" do
    let!(:project_dir) { TestProject.create_and_boot }

    after { TestProject.cleanup(project_dir) }

    it "returns all ISOs from YAML" do
      isos = described_class.all
      expect(isos.map(&:id)).to contain_exactly("debian-13-amd64", "debian-13-arm64")
    end

    it "returns ISO by id" do
      iso = described_class.find("debian-13-amd64")
      expect(iso.name).to eq("Debian 13.3.0 amd64 netinst")
      expect(iso.architecture).to eq("amd64")
    end

    it "raises RecordNotFound for unknown id" do
      expect { described_class.find("nonexistent") }.to raise_error(FlatRecord::RecordNotFound)
    end

    it "#to_h returns compact attributes hash" do
      h = described_class.find("debian-13-amd64").to_h
      expect(h).to include("name" => "Debian 13.3.0 amd64 netinst", "architecture" => "amd64")
      expect(h.values).not_to include(nil)
    end
  end

  describe "empty state" do
    let(:tmp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmp_dir) }

    it "returns empty array when no isos.yml exists" do
      FlatRecord.configure do |c|
        c.backend = :yaml
        c.data_paths = [tmp_dir]
        c.merge_strategy = :deep_merge
        c.id_strategy = :string
      end
      Pim::Profile.reload!
      Pim::Iso.reload!

      expect(described_class.all).to eq([])
    end
  end

  describe "#iso_path" do
    let!(:project_dir) { TestProject.create }

    after { TestProject.cleanup(project_dir) }

    it "returns Pathname under cache dir" do
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12", "filename" => "debian-12-netinst.iso" }
      ])
      TestProject.boot(project_dir)

      iso = described_class.find("debian-12")
      expected = Pathname.new(File.join(Pim::XDG_CACHE_HOME, 'pim', 'isos', 'debian-12-netinst.iso'))
      expect(iso.iso_path).to eq(expected)
    end

    it "uses filename attribute when present" do
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12", "filename" => "custom.iso" }
      ])
      TestProject.boot(project_dir)

      iso = described_class.find("debian-12")
      expect(iso.iso_path.basename.to_s).to eq("custom.iso")
    end

    it "falls back to id.iso when no filename" do
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12" }
      ])
      TestProject.boot(project_dir)

      iso = described_class.find("debian-12")
      expect(iso.iso_path.basename.to_s).to eq("debian-12.iso")
    end
  end

  describe "#downloaded?" do
    let!(:project_dir) { TestProject.create }

    after { TestProject.cleanup(project_dir) }

    before do
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12", "filename" => "test.iso" }
      ])
      TestProject.boot(project_dir)
    end

    it "returns false when file doesn't exist" do
      iso = described_class.find("debian-12")
      expect(iso.downloaded?).to be false
    end

    it "returns true when file exists" do
      iso = described_class.find("debian-12")
      iso_dir = File.join(Pim::XDG_CACHE_HOME, 'pim', 'isos')
      FileUtils.mkdir_p(iso_dir)
      FileUtils.touch(File.join(iso_dir, 'test.iso'))

      expect(iso.downloaded?).to be true
    ensure
      FileUtils.rm_f(File.join(iso_dir, 'test.iso'))
    end
  end

  describe "#verify" do
    let!(:project_dir) { TestProject.create }

    after { TestProject.cleanup(project_dir) }

    before do
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12", "filename" => "test.iso", "checksum" => "sha256:abcdef1234567890" }
      ])
      TestProject.boot(project_dir)
    end

    it "returns true when checksum matches" do
      iso = described_class.find("debian-12")
      allow(File).to receive(:exist?).and_call_original
      allow(Pathname).to receive(:new).and_call_original
      allow_any_instance_of(Pathname).to receive(:exist?).and_call_original
      path = iso.iso_path
      allow(path).to receive(:exist?).and_return(true)
      allow(iso).to receive(:iso_path).and_return(path)
      mock_digest = instance_double(Digest::SHA256, hexdigest: "abcdef1234567890")
      allow(Digest::SHA256).to receive(:file).with(path).and_return(mock_digest)

      expect(iso.verify(silent: true)).to be true
    end

    it "returns false when checksum doesn't match" do
      iso = described_class.find("debian-12")
      path = iso.iso_path
      allow(path).to receive(:exist?).and_return(true)
      allow(iso).to receive(:iso_path).and_return(path)
      mock_digest = instance_double(Digest::SHA256, hexdigest: "wrong_checksum")
      allow(Digest::SHA256).to receive(:file).with(path).and_return(mock_digest)

      expect(iso.verify(silent: true)).to be false
    end

    it "returns false when file doesn't exist" do
      iso = described_class.find("debian-12")
      expect(iso.verify(silent: true)).to be false
    end
  end

  describe "#download" do
    let!(:project_dir) { TestProject.create }
    let(:tmp_dir) { Dir.mktmpdir }

    after do
      TestProject.cleanup(project_dir)
      FileUtils.remove_entry(tmp_dir)
    end

    before do
      TestProject.write_records(project_dir, "isos", [
        { "id" => "debian-12", "filename" => "test.iso", "url" => "https://example.com/test.iso", "checksum" => "sha256:abc123" }
      ])
      TestProject.boot(project_dir)
    end

    it "calls Pim::HTTP.download and verify" do
      iso = described_class.find("debian-12")
      allow(iso.iso_path).to receive(:exist?).and_return(false)
      allow(iso.iso_path).to receive(:dirname).and_return(Pathname.new(tmp_dir))
      allow(Pathname.new(tmp_dir)).to receive(:mkpath)
      allow(Pim::HTTP).to receive(:download)
      allow(iso).to receive(:verify).and_return(true)

      iso.download
      expect(Pim::HTTP).to have_received(:download).with("https://example.com/test.iso", iso.iso_path.to_s)
    end
  end
end
