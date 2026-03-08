# frozen_string_literal: true

RSpec.describe Pim::IsosView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:id, :architecture, :name])
  end

  it "has detail fields" do
    expect(described_class.detail_fields).to include(:id, :name, :url)
  end
end
