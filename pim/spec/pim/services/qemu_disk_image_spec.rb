# frozen_string_literal: true

RSpec.describe Pim::QemuDiskImage do
  describe ".create_overlay" do
    it "calls qemu-img create with correct backing file args" do
      allow(FileUtils).to receive(:mkdir_p)
      expect(Open3).to receive(:capture2e)
        .with('qemu-img', 'create', '-f', 'qcow2', '-b', '/tmp/golden.qcow2', '-F', 'qcow2', '/tmp/overlay.qcow2')
        .and_return(["", double(success?: true)])

      result = described_class.create_overlay('/tmp/golden.qcow2', '/tmp/overlay.qcow2')
      expect(result).to be_a(described_class)
    end

    it "raises on failure" do
      allow(FileUtils).to receive(:mkdir_p)
      expect(Open3).to receive(:capture2e)
        .and_return(["error output", double(success?: false)])

      expect {
        described_class.create_overlay('/tmp/golden.qcow2', '/tmp/overlay.qcow2')
      }.to raise_error(Pim::QemuDiskImage::Error, /qemu-img failed/)
    end
  end

  describe ".clone" do
    it "calls qemu-img convert with correct format" do
      allow(FileUtils).to receive(:mkdir_p)
      expect(Open3).to receive(:capture2e)
        .with('qemu-img', 'convert', '-O', 'qcow2', '/tmp/source.qcow2', '/tmp/dest.qcow2')
        .and_return(["", double(success?: true)])

      result = described_class.clone('/tmp/source.qcow2', '/tmp/dest.qcow2')
      expect(result).to be_a(described_class)
    end

    it "raises on failure" do
      allow(FileUtils).to receive(:mkdir_p)
      expect(Open3).to receive(:capture2e)
        .and_return(["error output", double(success?: false)])

      expect {
        described_class.clone('/tmp/source.qcow2', '/tmp/dest.qcow2')
      }.to raise_error(Pim::QemuDiskImage::Error, /qemu-img failed/)
    end
  end
end
