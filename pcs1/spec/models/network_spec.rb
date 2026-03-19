# frozen_string_literal: true

RSpec.describe Pcs1::Network do
  before do
    TestProject.seed_all(test_dir)
  end

  let(:network) { Pcs1::Network.first }

  describe "#contains_ip?" do
    it "returns true for an IP within the subnet" do
      expect(network.contains_ip?("172.31.1.50")).to be true
    end

    it "returns false for an IP outside the subnet" do
      expect(network.contains_ip?("10.0.0.1")).to be false
    end

    it "returns true for the gateway IP" do
      expect(network.contains_ip?("172.31.1.1")).to be true
    end

    it "returns true for the network address" do
      expect(network.contains_ip?("172.31.1.0")).to be true
    end

    it "returns false for an adjacent subnet" do
      expect(network.contains_ip?("172.31.2.1")).to be false
    end
  end
end
