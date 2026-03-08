# frozen_string_literal: true

RSpec.describe Pim::HTTP do
  describe ".verify_checksum" do
    let(:tmp_file) { Tempfile.new('checksum_test') }

    before do
      tmp_file.write("test content")
      tmp_file.close
    end

    after { tmp_file.unlink }

    it "returns true for matching checksum" do
      expected = Digest::SHA256.file(tmp_file.path).hexdigest
      expect(described_class.verify_checksum(tmp_file.path, expected)).to be true
    end

    it "returns false for mismatching checksum" do
      expect(described_class.verify_checksum(tmp_file.path, "0" * 64)).to be false
    end

    it "strips sha256: prefix from expected value" do
      expected = Digest::SHA256.file(tmp_file.path).hexdigest
      expect(described_class.verify_checksum(tmp_file.path, "sha256:#{expected}")).to be true
    end
  end

  describe ".format_bytes" do
    it "formats zero bytes" do
      expect(described_class.format_bytes(0)).to eq("0 B")
    end

    it "formats bytes" do
      expect(described_class.format_bytes(512)).to match(/512\.00 B/)
    end

    it "formats megabytes" do
      expect(described_class.format_bytes(1024 * 1024)).to match(/1\.00 MB/)
    end

    it "formats gigabytes" do
      expect(described_class.format_bytes(1024 * 1024 * 1024)).to match(/1\.00 GB/)
    end
  end

  describe ".download" do
    it "raises on too many redirects" do
      expect {
        described_class.download("https://example.com/file", "/dev/null", redirect_limit: 0)
      }.to raise_error("Too many redirects")
    end
  end
end
