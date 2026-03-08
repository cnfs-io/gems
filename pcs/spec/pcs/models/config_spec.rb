# frozen_string_literal: true

RSpec.describe Pcs::Config do
  describe "#networking" do
    it "has sensible defaults" do
      c = Pcs::Config.new
      expect(c.networking.dns_fallback_resolvers).to eq(["1.1.1.1", "8.8.8.8"])
    end

    it "accepts block configuration" do
      c = Pcs::Config.new
      c.networking do |net|
        net.dns_fallback_resolvers = ["8.8.8.8"]
      end
      expect(c.networking.dns_fallback_resolvers).to eq(["8.8.8.8"])
    end
  end

  describe "#flat_record" do
    it "has sensible defaults" do
      c = Pcs::Config.new
      expect(c.flat_record.backend).to eq(:yaml)
      expect(c.flat_record.id_strategy).to eq(:integer)
    end

    it "accepts block configuration" do
      c = Pcs::Config.new
      c.flat_record do |fr|
        fr.backend = :json
      end
      expect(c.flat_record.backend).to eq(:json)
    end
  end

  describe "#service" do
    it "has dnsmasq defaults" do
      c = Pcs::Config.new
      expect(c.service.dnsmasq.proxy).to eq(true)
      expect(c.service.dnsmasq.config_dir).to eq(Pathname.new("/etc/dnsmasq.d"))
    end

    it "has netboot defaults" do
      c = Pcs::Config.new
      expect(c.service.netboot.image).to eq("docker.io/netbootxyz/netbootxyz")
      expect(c.service.netboot.ipxe_timeout).to eq(10)
      expect(c.service.netboot.default_os).to eq("debian-trixie")
      expect(c.service.netboot.netboot_dir).to eq(Pathname.new("/opt/pcs/netboot"))
    end

    it "has proxmox defaults" do
      c = Pcs::Config.new
      pve = c.service.proxmox
      expect(pve.default_preseed_interface).to eq("enp1s0")
      expect(pve.default_preseed_device).to eq("/dev/sda")
      expect(pve.reboot_initial_wait).to eq(30)
      expect(pve.reboot_poll_interval).to eq(15)
      expect(pve.reboot_max_attempts).to eq(20)
      expect(pve.web_port).to eq(8006)
    end

    it "accepts block configuration" do
      c = Pcs::Config.new
      c.service.dnsmasq do |dns|
        dns.proxy = false
      end
      expect(c.service.dnsmasq.proxy).to eq(false)
    end
  end

  describe "#discovery" do
    it "has default probe credentials" do
      c = Pcs::Config.new
      expect(c.discovery.users).to include("root")
      expect(c.discovery.passwords).to include("changeme123!")
    end
  end

  describe "preseed defaults" do
    it "has sensible defaults" do
      c = Pcs::Config.new
      expect(c.default_root_password).to eq("changeme123!")
      expect(c.default_locale).to eq("en-us")
      expect(c.default_packages).to eq("openssh-server curl sudo")
    end
  end
end

RSpec.describe "ProjectConfig removal" do
  it "does not define Pcs::ProjectConfig" do
    expect(defined?(Pcs::ProjectConfig)).to be_nil
  end

  it "does not have project_config on Pcs" do
    expect(Pcs).not_to respond_to(:project_config)
  end
end

RSpec.describe "Pcs.config integration", :uses_fixture_project do
  it "loads networking from pcs.rb" do
    expect(Pcs.config.networking.dns_fallback_resolvers).to eq(["1.1.1.1", "8.8.8.8"])
  end

  it "loads flat_record from pcs.rb" do
    expect(Pcs.config.flat_record.backend).to eq(:yaml)
  end
end
