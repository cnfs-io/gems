# frozen_string_literal: true

RSpec.describe Pcs1::Config do
  describe "defaults" do
    let(:config) { Pcs1::Config.new }

    it "has a default log level" do
      expect(config.log_level).to eq(:info)
    end

    it "has a default log output" do
      expect(config.log_output).to eq($stdout)
    end
  end

  describe "dnsmasq defaults" do
    let(:dnsmasq) { Pcs1::DnsmasqConfig.new }

    it "has default config path" do
      expect(dnsmasq.config_path).to eq("/etc/dnsmasq.d/pcs.conf")
    end

    it "has default interface" do
      expect(dnsmasq.interface).to eq("eth0")
    end

    it "has default DHCP range octets" do
      expect(dnsmasq.range_start_octet).to eq(100)
      expect(dnsmasq.range_end_octet).to eq(200)
    end

    it "has default lease time" do
      expect(dnsmasq.lease_time).to eq("12h")
    end
  end

  describe "netboot defaults" do
    let(:netboot) { Pcs1::NetbootConfig.new }

    it "has default ports" do
      expect(netboot.tftp_port).to eq(69)
      expect(netboot.http_port).to eq(8080)
    end

    it "has default boot files" do
      expect(netboot.boot_file_bios).to include("kpxe")
      expect(netboot.boot_file_efi).to include("efi")
    end
  end
end
