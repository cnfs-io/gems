# frozen_string_literal: true

RSpec.describe Pim::Config do
  before { Pim.reset! }

  it "provides sensible defaults" do
    config = Pim.configure
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

  it "accepts overrides via configure block" do
    Pim.configure do |c|
      c.serve_port = 9090
      c.iso_dir = "/custom/isos"
    end
    expect(Pim.config.serve_port).to eq(9090)
    expect(Pim.config.iso_dir).to eq("/custom/isos")
  end

  it "provides vm defaults: persistent clone, bridged, no USB" do
    vm = Pim.config.vm
    expect(vm.disk).to eq("clone")
    expect(vm.network).to eq("bridged")
    expect(vm.bridge).to be_nil
    expect(vm.usb).to eq([])
  end

  it "allows ENV in config values" do
    Pim.configure do |c|
      c.iso_dir = ENV.fetch("PIM_ISO_DIR", "/custom/isos")
    end
    expect(Pim.config.iso_dir).to eq("/custom/isos")
  end

  it "returns config via Pim.config without explicit configure" do
    config = Pim.config
    expect(config).to be_a(Pim::Config)
    expect(config.serve_port).to eq(8080)
  end

  it "provides images defaults" do
    config = Pim.config
    expect(config.images.require_label).to be true
    expect(config.images.auto_publish).to be false
  end

  it "supports images nested config" do
    Pim.configure do |c|
      c.images do |img|
        img.require_label = false
        img.auto_publish = true
      end
    end
    expect(Pim.config.images.require_label).to be false
    expect(Pim.config.images.auto_publish).to be true
  end
end
