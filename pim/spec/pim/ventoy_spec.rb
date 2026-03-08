# frozen_string_literal: true

RSpec.describe Pim::VentoyConfig do
  before do
    Pim.reset!
    Pim.configure do |c|
      c.ventoy do |v|
        v.version = 'v1.0.99'
        v.dir = 'ventoy-1.0.99'
        v.file = 'ventoy-1.0.99-linux.tar.gz'
        v.url = 'https://example.com/ventoy.tar.gz'
        v.checksum = 'sha256:abc123'
        v.device = '/dev/sdX'
      end
    end
  end

  after { Pim.reset! }

  describe "#url" do
    it "returns the configured URL" do
      config = described_class.new
      expect(config.url).to eq('https://example.com/ventoy.tar.gz')
    end

    it "returns nil when url not in config" do
      Pim.reset!
      config = described_class.new
      expect(config.url).to be_nil
    end
  end

  describe "#version" do
    it "returns the configured version" do
      config = described_class.new
      expect(config.version).to eq('v1.0.99')
    end
  end

  describe "#ventoy_dir" do
    it "returns path under XDG_CACHE_HOME" do
      config = described_class.new
      expect(config.ventoy_dir.to_s).to include('pim/ventoy/ventoy-1.0.99')
    end
  end

  describe "#mount_point" do
    it "returns mnt path under XDG_CACHE_HOME" do
      config = described_class.new
      expect(config.mount_point.to_s).to include('pim/ventoy/mnt')
    end
  end
end

RSpec.describe Pim::VentoyManager do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:cache_dir) { File.join(tmp_dir, 'cache') }
  let(:ventoy_dir) { File.join(cache_dir, 'ventoy-1.0.99') }

  let(:config) do
    config = instance_double(Pim::VentoyConfig,
      version: 'v1.0.99',
      dir: 'ventoy-1.0.99',
      file: 'ventoy-1.0.99-linux.tar.gz',
      url: 'https://example.com/ventoy.tar.gz',
      checksum: 'sha256:abc123',
      ventoy_dir: Pathname.new(ventoy_dir),
      mount_point: Pathname.new(File.join(cache_dir, 'mnt')),
      iso_dir: Pathname.new(File.join(cache_dir, 'isos')),
      device: nil
    )
    config
  end

  after { FileUtils.remove_entry(tmp_dir) }

  describe "#ensure_ventoy!" do
    it "returns immediately if Ventoy2Disk.sh already exists" do
      FileUtils.mkdir_p(ventoy_dir)
      FileUtils.touch(File.join(ventoy_dir, 'Ventoy2Disk.sh'))

      manager = described_class.new(config: config)
      expect(Pim::HTTP).not_to receive(:download)
      expect(manager.ensure_ventoy!).to be true
    end

    it "exits with error if URL not configured" do
      allow(config).to receive(:url).and_return(nil)
      Pim.console_mode!

      manager = described_class.new(config: config)
      expect { manager.ensure_ventoy! }.to raise_error(
        Pim::CommandError, /URL and checksum must be configured/
      )
    end

    it "exits with error if checksum not configured" do
      allow(config).to receive(:checksum).and_return(nil)
      Pim.console_mode!

      manager = described_class.new(config: config)
      expect { manager.ensure_ventoy! }.to raise_error(
        Pim::CommandError, /URL and checksum must be configured/
      )
    end

    it "downloads tarball when not cached" do
      Pim.console_mode!

      manager = described_class.new(config: config)

      # Stub XDG_CACHE_HOME to use our tmp dir
      stub_const("Pim::XDG_CACHE_HOME", tmp_dir)
      allow(config).to receive(:ventoy_dir).and_return(
        Pathname.new(File.join(tmp_dir, 'pim', 'ventoy', 'ventoy-1.0.99'))
      )
      allow(config).to receive(:mount_point).and_return(
        Pathname.new(File.join(tmp_dir, 'pim', 'ventoy', 'mnt'))
      )

      tarball_path = File.join(tmp_dir, 'pim', 'ventoy', 'ventoy-1.0.99-linux.tar.gz')

      expect(Pim::HTTP).to receive(:download).with(
        'https://example.com/ventoy.tar.gz', tarball_path
      ) do
        # Simulate download by creating the file
        FileUtils.mkdir_p(File.dirname(tarball_path))
        File.write(tarball_path, "fake tarball")
      end

      expect(Pim::HTTP).to receive(:verify_checksum).and_return(true)

      # Stub extraction to create the expected directory
      expect(manager).to receive(:extract_tarball) do |_tarball, dest|
        ventoy_extract_dir = File.join(dest, 'ventoy-1.0.99')
        FileUtils.mkdir_p(ventoy_extract_dir)
        FileUtils.touch(File.join(ventoy_extract_dir, 'Ventoy2Disk.sh'))
      end

      expect(manager.ensure_ventoy!).to be true
    end

    it "exits with error and deletes tarball if checksum fails" do
      Pim.console_mode!

      manager = described_class.new(config: config)

      stub_const("Pim::XDG_CACHE_HOME", tmp_dir)
      allow(config).to receive(:ventoy_dir).and_return(
        Pathname.new(File.join(tmp_dir, 'pim', 'ventoy', 'ventoy-1.0.99'))
      )
      allow(config).to receive(:mount_point).and_return(
        Pathname.new(File.join(tmp_dir, 'pim', 'ventoy', 'mnt'))
      )

      tarball_path = File.join(tmp_dir, 'pim', 'ventoy', 'ventoy-1.0.99-linux.tar.gz')

      expect(Pim::HTTP).to receive(:download) do
        FileUtils.mkdir_p(File.dirname(tarball_path))
        File.write(tarball_path, "fake tarball")
      end

      expect(Pim::HTTP).to receive(:verify_checksum).and_return(false)

      expect { manager.ensure_ventoy! }.to raise_error(
        Pim::CommandError, /Checksum verification failed/
      )

      expect(File.exist?(tarball_path)).to be false
    end
  end

  describe "#show_config" do
    it "includes url in output" do
      manager = described_class.new(config: config)
      expect { manager.show_config }.to output(/url:.*example\.com/).to_stdout
    end
  end
end
