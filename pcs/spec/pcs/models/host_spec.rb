# frozen_string_literal: true

RSpec.describe Pcs::Host do
  it "starts discovered, untyped, and is found as its type once it has one" do
    found = host
    expect(found.status).to eq("discovered")
    expect(found.class).to eq(described_class)

    debian = found.becomes!(Pcs::DebianHost)
    expect(described_class.find(debian.id)).to be_a(Pcs::DebianHost)
  end

  it "rejects unknown types, bad hostnames, roles and arches" do
    bad = described_class.new(type: "toaster", hostname: "Bad_Name", role: "boss", arch: "sparc")
    expect(bad).not_to be_valid
    expect(bad.errors.attribute_names).to include(:type, :hostname, :role, :arch)
  end

  describe "a Debian host (installed over PXE)" do
    let(:debian) { host(Pcs::DebianHost) }

    it "needs a hostname, configured IP, disk and a control plane to install from, but no key" do
      expect(debian.missing_configuration).to eq(%i[hostname configured_ip disk control_plane_ip])
      expect(debian.configure).to be(false)

      control_plane
      debian.update!(hostname: "node1", disk: "/dev/sda")
      debian.primary_interface.update!(configured_ip: "10.0.0.11")
      reloaded = described_class.find(debian.id)
      expect(reloaded.configure).to be(true)
      expect(described_class.find(debian.id).status).to eq("configured")
    end
  end

  describe "a PiKVM (keyed over SSH)" do
    let(:kvm) { host(Pcs::PikvmHost, hostname: "kvm1", configured_ip: "10.0.0.20") }

    it "must be keyed before it's configured" do
      expect(kvm.configure).to be(false)
      expect(kvm.key).to be(true)
      expect(kvm.configure).to be(true)
      expect(kvm.provision).to be(true)
      expect(described_class.find(kvm.id).status).to eq("provisioned")
    end
  end

  it "keeps its status and type through a save and reload" do
    kvm = host(Pcs::PikvmHost, hostname: "kvm1", configured_ip: "10.0.0.20")
    kvm.key
    kvm.save!
    expect(described_class.find(kvm.id)).to have_attributes(status: "keyed", class: Pcs::PikvmHost)
  end

  it "has an fqdn in the site's domain" do
    expect(host(hostname: "node1").fqdn).to eq("node1.sg.lan")
  end
end
