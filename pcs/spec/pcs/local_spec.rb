# frozen_string_literal: true

RSpec.describe Pcs::Local do
  it "turns the machine's name into a DNS label" do
    { "Roberto's-MacBook-Pro.local" => "roberto-s-macbook-pro", "cp1" => "cp1", "PI_4" => "pi-4" }.each do |raw, label|
      allow(Socket).to receive(:gethostname).and_return(raw)
      expect(described_class.hostname).to eq(label)
    end
  end

  it "finds real IPv4 interfaces with their subnets" do
    expect(described_class.interfaces).to all(have_attributes(ip: /\A\d+\.\d+\.\d+\.\d+\z/))
    expect(described_class.interfaces.map(&:name)).not_to include("lo", "lo0")
  end
end
