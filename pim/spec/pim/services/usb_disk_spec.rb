# frozen_string_literal: true

RSpec.describe Pim::UsbDisk do
  # Trimmed `ioreg -r -c IOUSBHostDevice -l` output: two sticks, one with a partition
  let(:ioreg) do
    <<~IOREG
      +-o Mass Storage@01131000  <class IOUSBHostDevice>
          "idProduct" = 25479
          "idVendor" = 1423
          "USB Product Name" = "Mass Storage"
            | +-o IOMedia
            |     "BSD Name" = "disk5"
            |     "BSD Name" = "disk5s1"
      +-o ESD310C@01220000  <class IOUSBHostDevice>
          "idProduct" = 8448
          "idVendor" = 8564
            | +-o IOMedia
            |     "BSD Name" = "disk4"
    IOREG
  end

  describe ".macos_disks" do
    it "maps VID:PID to the whole-disk BSD name" do
      expect(described_class.macos_disks(ioreg)).to eq("058f:6387" => "disk5", "2174:2100" => "disk4")
    end
  end

  describe ".resolve" do
    it "resolves a USB ID to its disk on macOS" do
      allow(described_class).to receive(:macos?).and_return(true)
      allow(described_class).to receive(:macos_disks).and_return("058f:6387" => "disk5")

      expect(described_class.resolve("058F:6387")).to eq("/dev/disk5")
    end

    it "raises when the USB ID is not plugged in" do
      allow(described_class).to receive(:macos?).and_return(true)
      allow(described_class).to receive(:macos_disks).and_return({})

      expect { described_class.resolve("dead:beef") }.to raise_error(described_class::Error, /not found/)
    end

    it "requires a device path for USB IDs off macOS" do
      allow(described_class).to receive(:macos?).and_return(false)

      expect { described_class.resolve("058f:6387") }.to raise_error(described_class::Error, /only work on macOS/)
    end

    it "rejects paths that are not block devices" do
      expect { described_class.resolve(Dir.tmpdir) }.to raise_error(described_class::Error, /not a block device/)
    end
  end

  describe ".qemu_path" do
    it "uses the raw device on macOS" do
      allow(described_class).to receive(:macos?).and_return(true)
      expect(described_class.qemu_path("/dev/disk5")).to eq("/dev/rdisk5")
    end

    it "keeps the path elsewhere" do
      allow(described_class).to receive(:macos?).and_return(false)
      expect(described_class.qemu_path("/dev/sdb")).to eq("/dev/sdb")
    end
  end
end
