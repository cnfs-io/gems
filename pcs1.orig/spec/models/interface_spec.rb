# frozen_string_literal: true

RSpec.describe Pcs1::Interface do
  before do
    TestProject.seed_all(test_dir)
  end

  let(:interface) { Pcs1::Interface.first }

  describe "#configured?" do
    it "returns true when configured_ip is set" do
      expect(interface.configured?).to be true
    end

    it "returns false when configured_ip is nil" do
      interface.configured_ip = nil
      expect(interface.configured?).to be false
    end

    it "returns false when configured_ip is empty" do
      interface.configured_ip = ""
      expect(interface.configured?).to be false
    end
  end

  describe "#reachable_ip" do
    it "returns configured_ip when set" do
      expect(interface.reachable_ip).to eq("172.31.1.20")
    end

    it "falls back to discovered_ip when configured_ip is nil" do
      interface.configured_ip = nil
      expect(interface.reachable_ip).to eq("172.31.1.100")
    end
  end
end
