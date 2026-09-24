# frozen_string_literal: true

RSpec.describe Pcs::Operations::Scan do
  # Stands in for Adapters::Nmap: the same answer for every subnet.
  let(:nmap) do
    answer = found
    Object.new.tap { |o| o.define_singleton_method(:scan) { |_subnet| answer } }
  end

  def found_at(ip, mac: nil, vendor: nil, hostname: nil)
    Pcs::Adapters::Nmap::Found.new(ip:, mac:, vendor:, hostname:)
  end

  let(:found) do
    [
      found_at("10.0.0.2"), # the control plane itself
      found_at("10.0.0.77", mac: "aa:bb:cc:00:00:01", vendor: "Intel"), # a known host, moved
      found_at("10.0.0.9", mac: "d8:3a:dd:11:22:33", vendor: "Raspberry Pi", hostname: "kvm1.sg.lan"),
      found_at("10.0.0.10", hostname: "Not A Label")
    ]
  end

  let!(:cp) { control_plane }
  let!(:known) { host(hostname: "n1") }

  def scan(**opts)
    described_class.new(networks: [network], nmap:, out: StringIO.new, **opts).call!
  end

  it "adds new machines as discovered hosts, and updates known ones by MAC, else IP" do
    expect(scan.value.to_h).to eq(added: 2, updated: 1, unchanged: 1)

    expect(known.interfaces.first).to have_attributes(discovered_ip: "10.0.0.77", vendor: "Intel")
    expect(cp.interfaces.first.discovered_ip).to be_nil

    kvm = Pcs::Interface.find_by(mac: "d8:3a:dd:11:22:33")
    expect(kvm.host).to have_attributes(hostname: "kvm1", status: "discovered", type: nil)
    expect(kvm).to have_attributes(discovered_ip: "10.0.0.9", network_id: network.id)
    expect(Pcs::Interface.with_ip("10.0.0.10").host.hostname).to be_nil
  end

  it "finds nothing new the second time" do
    scan
    expect(scan.value.to_h).to eq(added: 0, updated: 0, unchanged: 4)
  end

  it "only lists the changes in a dry run" do
    op = scan(dry_run: true)
    expect(op.steps.map(&:description)).to eq([
                                                "update n1: vendor Intel, discovered_ip 10.0.0.77",
                                                "add host kvm1 (10.0.0.9, d8:3a:dd:11:22:33, Raspberry Pi)",
                                                "add host 10.0.0.10 (10.0.0.10)"
                                              ])
    expect(Pcs::Host.count).to eq(2)
    expect(known.interfaces.first.discovered_ip).to eq("10.0.0.50")
  end
end
