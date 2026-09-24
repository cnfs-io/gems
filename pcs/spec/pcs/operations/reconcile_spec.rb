# frozen_string_literal: true

RSpec.describe Pcs::Operations::Reconcile do
  let(:system) { pcm_system }

  let!(:node) do
    control_plane
    host(Pcs::DebianHost, hostname: "n1", disk: "/dev/sda", arch: "arm64", mac: "aa:bb:cc:00:00:01",
                          configured_ip: "10.0.0.11")
  end

  def reconcile(**opts)
    described_class.new(settings:, pcm:, download:, out: StringIO.new, **opts).call!
  end

  def volume(path) = @tmpdir.join("volumes", path).read
  def menu(mac_hex) = volume("netboot/config/menus/MAC-#{mac_hex}.ipxe")

  it "points PXE clients at the control plane, leaving DHCP to the site (proxy mode)" do
    reconcile
    conf = volume("dnsmasq/dnsmasq.d/pcs.conf")
    expect(conf).to include("dhcp-range=10.0.0.0,proxy,255.255.255.0",
                            'pxe-service=x86-64_EFI,"netboot.xyz (UEFI)",netboot.xyz.efi,10.0.0.2',
                            "port=0")
    expect(conf).not_to include("dhcp-host", "enable-tftp")
  end

  it "reserves configured hosts' addresses in dhcp mode" do
    settings.dnsmasq.mode = "dhcp"
    expect { reconcile }.to raise_error(Pcs::Error, /needs a gateway, dhcp start and dhcp end on primary/)

    network.update!(dhcp_start: "10.0.0.100", dhcp_end: "10.0.0.199")
    reconcile
    expect(volume("dnsmasq/dnsmasq.d/pcs.conf")).to include("dhcp-range=10.0.0.100,10.0.0.199,255.255.255.0,12h",
                                                            "dhcp-host=aa:bb:cc:00:00:01,10.0.0.11,n1")
  end

  it "gives each host a boot menu with its own settings, booting the disk unless an install is asked for" do
    host(Pcs::DebianHost, hostname: "n2", disk: "/dev/nvme0n1", mac: "aa:bb:cc:00:00:02", configured_ip: "10.0.0.12")
    reconcile

    n1 = menu("aabbcc000001")
    expect(n1).to include("--default local", "http://10.0.0.2:8080/debian-installer/trixie/arm64/linux",
                          "netcfg/get_ipaddress=10.0.0.11", "netcfg/get_gateway=10.0.0.1", "hostname=n1",
                          "preseed/url=http://10.0.0.2:8080/pcs/n1.preseed.cfg")
    expect(menu("aabbcc000002")).to include("netcfg/get_ipaddress=10.0.0.12", "hostname=n2", "amd64")
    expect(menu("aabbcc000002")).not_to include("10.0.0.11")

    node.update!(pxe_install: true)
    reconcile
    expect(menu("aabbcc000001")).to include("--default install")
  end

  it "writes preseeds holding the public key only, and no password unless it's a hash" do
    reconcile
    preseed = volume("netboot/assets/pcs/n1.preseed.cfg")
    expect(preseed).to include("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPublicPart pcs",
                               "user-password-crypted password !", "password-authentication boolean false",
                               "linux-image-arm64", "partman-auto/disk string /dev/sda",
                               "time/zone string Asia/Singapore")
    expect(preseed).not_to include("PRIVATE", "secret", "me@laptop")

    settings.install.password_hash = "hunter2"
    expect { reconcile }.to raise_error(Pcs::Error, /SHA-512 crypt hash/)

    settings.install.password_hash = "$6$salt$Zm9vYmFy.hash/"
    reconcile
    expect(volume("netboot/assets/pcs/n1.preseed.cfg"))
      .to include("user-password-crypted password $6$salt$Zm9vYmFy.hash/")
  end

  it "refuses a private key where the public key should be" do
    Pathname("#{key_path}.pub").write(File.read(key_path))
    expect { reconcile }.to raise_error(Pcs::Error, /holds a private key/)
  end

  it "fetches the installer for the hosts' architecture, with firmware if asked for, once" do
    settings.install.firmware = true
    reconcile
    expect(downloads).to eq([
                              "http://deb.debian.org/debian/dists/trixie/main/installer-arm64/current/images/netboot/debian-installer/arm64/linux",
                              "http://deb.debian.org/debian/dists/trixie/main/installer-arm64/current/images/netboot/debian-installer/arm64/initrd.gz",
                              "https://cdimage.debian.org/cdimage/firmware/trixie/current/firmware.cpio.gz"
                            ])
    expect(volume("netboot/assets/debian-installer/trixie/arm64/initrd-firmware.gz"))
      .to eq("<initrd.gz><firmware.cpio.gz>")
    expect(menu("aabbcc000001")).to include("initrd=initrd-firmware.gz", "arm64/initrd-firmware.gz ||")

    downloads.clear
    expect(reconcile.steps).to be_empty
    expect(downloads).to be_empty
  end

  it "uses the installer's own initrd by default" do
    reconcile
    expect(downloads.map { |url| File.basename(url) }).to eq(%w[linux initrd.gz])
    expect(volume("netboot/assets/debian-installer/trixie/arm64/initrd.gz")).to eq("<initrd.gz>")
  end

  it "restarts dnsmasq only when its config changes" do
    reconcile
    expect(system.commands).to include(%w[pcm __compose restart dnsmasq])

    system.commands.clear
    node.update!(disk: "/dev/sdb")
    reconcile
    expect(system.commands).not_to include(%w[pcm __compose restart dnsmasq])
  end

  it "removes its files for hosts that are gone, and leaves others' files alone" do
    reconcile
    menus = @tmpdir.join("volumes/netboot/config/menus")
    menus.join("MAC-ffffffffffff.ipxe").write("#!ipxe\n# someone else's\n")

    node.destroy
    reconcile
    expect(menus.children.map { |f| f.basename.to_s }).to eq(["MAC-ffffffffffff.ipxe"])
    expect(@tmpdir.join("volumes/netboot/assets/pcs").children).to be_empty
  end

  it "skips hosts that aren't configured enough to install" do
    node.update!(disk: nil)
    expect(reconcile.value).to be_empty
    expect(@tmpdir.join("volumes/netboot/config/menus")).not_to exist
  end

  it "only lists the changes in a dry run" do
    op = reconcile(dry_run: true)
    expect(op.steps.map(&:description)).to include(a_string_matching(/write .*pcs\.conf/),
                                                   a_string_matching(/write .*MAC-aabbcc000001\.ipxe/))
    expect(@tmpdir.join("volumes")).not_to exist
    expect(downloads).to be_empty
  end

  it "uses the project's own copy of a template" do
    project = @tmpdir.join("site")
    project.join("templates").mkpath
    project.join("config.ru").write("")
    project.join("templates", "post-install.sh.erb").write("#!/bin/sh\n# Generated by pcs\napt-get install -y htop\n")
    Dir.chdir(project) { reconcile }
    expect(volume("netboot/assets/pcs/n1.post-install.sh")).to include("apt-get install -y htop")
  end
end
