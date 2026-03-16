# frozen_string_literal: true

RSpec.describe Pcs::Adapters::Dnsmasq do
  describe ".prefix_to_netmask" do
    subject { described_class.send(:prefix_to_netmask, prefix) }

    context "with /24" do
      let(:prefix) { 24 }
      it { is_expected.to eq("255.255.255.0") }
    end

    context "with /22" do
      let(:prefix) { 22 }
      it { is_expected.to eq("255.255.252.0") }
    end

    context "with /25" do
      let(:prefix) { 25 }
      it { is_expected.to eq("255.255.255.128") }
    end

    context "with /16" do
      let(:prefix) { 16 }
      it { is_expected.to eq("255.255.0.0") }
    end
  end
end
