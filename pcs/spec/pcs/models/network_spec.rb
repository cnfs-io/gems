# frozen_string_literal: true

RSpec.describe Pcs::Network do
  it "knows its range, netmask and resolvers" do
    net = described_class.new(name: "lan", subnet: "10.0.0.0/24", dns_resolvers: "1.1.1.1, 8.8.8.8")
    expect(net.contains?("10.0.0.200")).to be(true)
    expect(net.contains?("10.0.1.1")).to be(false)
    expect(net.contains?("not an ip")).to be(false)
    expect(net.netmask).to eq("255.255.255.0")
    expect(net.dns_list).to eq(%w[1.1.1.1 8.8.8.8])
  end

  it "validates the subnet and that the gateway is inside it" do
    expect(described_class.new(name: "a", subnet: "10.0.0.5").tap(&:valid?).errors[:subnet]).to be_present
    expect(described_class.new(name: "b", subnet: "10.0.0.0/24", gateway: "10.9.9.1").tap(&:valid?).errors[:gateway])
      .to be_present
  end
end

RSpec.describe Pcs::Interface do
  it "normalises and validates MACs, and keeps configured IPs inside the network" do
    iface = described_class.new(network_id: network.id, mac: " AA:BB:CC:DD:EE:FF ", configured_ip: "192.168.9.9")
    expect(iface.mac).to eq("aa:bb:cc:dd:ee:ff")
    expect(iface).not_to be_valid
    expect(iface.errors[:configured_ip].first).to include("not in primary")
    expect(described_class.new(mac: "nope").tap(&:valid?).errors[:mac]).to be_present
  end

  it "is reachable at its configured IP once it has one" do
    iface = described_class.new(discovered_ip: "10.0.0.50")
    expect(iface.reachable_ip).to eq("10.0.0.50")
    iface.configured_ip = "10.0.0.11"
    expect(iface.reachable_ip).to eq("10.0.0.11")
  end
end
