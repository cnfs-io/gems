# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pcs::Role, :uses_fixture_project do
  it "loads roles from YAML" do
    expect(described_class.all.size).to eq(4)
  end

  it "returns role names" do
    expect(described_class.names).to contain_exactly("node", "nas", "kvm", "cp")
  end

  it "returns types for a role" do
    expect(described_class.types_for("node")).to eq(["proxmox", "vmware"])
  end

  it "returns types for single-type role" do
    expect(described_class.types_for("cp")).to eq(["rpi"])
  end

  it "returns empty array for unknown role" do
    expect(described_class.types_for("unknown")).to eq([])
  end

  it "computes octet for a role" do
    expect(described_class.octet_for("node", 0)).to eq(41)
    expect(described_class.octet_for("node", 2)).to eq(43)
  end

  it "computes octet for cp role" do
    expect(described_class.octet_for("cp")).to eq(11)
  end

  it "is read-only" do
    expect(described_class).to be_read_only
  end

  it "is not a hierarchy child" do
    expect(described_class.hierarchy_child?).to be false
  end
end
