# frozen_string_literal: true

RSpec.describe Pim::Config do
  before { Pim.reset! }

  it "has iso_dir with XDG default" do
    config = Pim::Config.new
    expect(config.iso_dir).to include("pim/isos")
  end

  it "has image_dir with XDG default" do
    config = Pim::Config.new
    expect(config.image_dir).to include("pim/images")
  end

  it "does not respond to memory" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:memory)
  end

  it "does not respond to cpus" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:cpus)
  end

  it "does not respond to disk_size" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:disk_size)
  end

  it "accepts overrides via configure block" do
    Pim.configure do |c|
      c.serve_port = 9090
      c.iso_dir = "/custom/isos"
    end
    expect(Pim.config.serve_port).to eq(9090)
    expect(Pim.config.iso_dir).to eq("/custom/isos")
  end

  it "returns config via Pim.config without explicit configure" do
    expect(Pim.config).to be_a(Pim::Config)
  end

  it "provides sensible defaults" do
    config = Pim::Config.new
    expect(config.serve_port).to eq(8080)
  end

  it "does not respond to ssh_user" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:ssh_user)
  end

  it "does not respond to ssh_timeout" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:ssh_timeout)
  end

  it "allows ENV in config values" do
    Pim.configure do |c|
      c.iso_dir = ENV.fetch("PIM_ISO_DIR", "~/.cache/pim/isos")
    end
    expect(Pim.config.iso_dir).to eq("~/.cache/pim/isos")
  end

  it "supports ventoy nested config" do
    Pim.configure do |c|
      c.ventoy do |v|
        v.version = "1.0.99"
        v.device = "/dev/sdX"
      end
    end
    expect(Pim.config.ventoy.version).to eq("1.0.99")
    expect(Pim.config.ventoy.device).to eq("/dev/sdX")
  end

  describe "flat_record nested config" do
    it "yields a FlatRecordSettings object" do
      config = Pim::Config.new
      config.flat_record do |fr|
        expect(fr).to be_a(Pim::FlatRecordSettings)
        fr.backend = :json
      end
      expect(config.flat_record.backend).to eq(:json)
    end

    it "has sensible defaults" do
      config = Pim::Config.new
      expect(config.flat_record.backend).to eq(:yaml)
      expect(config.flat_record.id_strategy).to eq(:string)
    end
  end
end
