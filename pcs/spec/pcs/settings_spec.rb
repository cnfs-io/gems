# frozen_string_literal: true

RSpec.describe Pcs::Settings do
  it "puts dnsmasq and netboot files under pcm's volumes, where the containers mount them" do
    settings = described_class.new
    settings.pcm_volumes_home = "/home/pi/.local/share/pcm/volumes"
    expect(settings.dnsmasq.config_dir).to eq("/home/pi/.local/share/pcm/volumes/dnsmasq/dnsmasq.d")
    expect(settings.netboot.menus_dir).to eq("/home/pi/.local/share/pcm/volumes/netboot/config/menus")
    expect(settings.netboot.assets_dir).to eq("/home/pi/.local/share/pcm/volumes/netboot/assets")
  end

  it "follows PCM_VOLUMES_HOME, and a renamed pcm service" do
    settings = described_class.new
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PCM_VOLUMES_HOME").and_return("/srv/pcm")
    settings.netboot.service = "pxe"
    expect(settings.netboot.assets_dir).to eq("/srv/pcm/pxe/assets")
  end

  it "defaults to proxy DHCP and key-only logins" do
    settings = described_class.new
    expect(settings.dnsmasq.mode).to eq("proxy")
    expect(settings.install.password_hash).to be_nil
    expect(settings.install.firmware).to be(false)
    expect(settings.install.firmware_url).to end_with("/firmware/trixie/current/firmware.cpio.gz")
  end
end
