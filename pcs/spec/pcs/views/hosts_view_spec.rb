# frozen_string_literal: true

RSpec.describe Pcs::HostsView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:id, :hostname, :type, :role, :status])
  end

  it "has detail fields" do
    expect(described_class.detail_fields).to include(:id, :hostname, :role, :arch)
  end

  it "has_many interfaces association for view" do
    assoc = described_class._view_associations.find { |a| a[:name] == :interfaces }
    expect(assoc).not_to be_nil
    expect(assoc[:columns]).to eq([:name, :network_name, :ip, :mac])
  end
end
