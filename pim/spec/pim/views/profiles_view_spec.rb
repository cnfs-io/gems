# frozen_string_literal: true

RSpec.describe Pim::ProfilesView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has list columns" do
    expect(described_class.columns).to eq([:id, :hostname, :username])
  end
end
