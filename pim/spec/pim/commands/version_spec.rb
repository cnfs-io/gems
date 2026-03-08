# frozen_string_literal: true

RSpec.describe Pim::Commands::Version do
  it "prints the pim version" do
    expect { subject.call }.to output(/pim #{Pim::VERSION}/).to_stdout
  end
end
