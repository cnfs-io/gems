# frozen_string_literal: true

RSpec.describe Pcs::SitesView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:name, :domain])
  end
end
