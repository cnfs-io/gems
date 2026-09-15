# frozen_string_literal: true

require "pim"
require_relative "support/test_project"

# Keep the developer's ~/.config/pim/pim.rb out of the specs
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("pim-spec-config-")

RSpec.configure do |config|
  config.filter_run_excluding integration: true
  config.filter_run_excluding e2e: true
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.order = :random
end
