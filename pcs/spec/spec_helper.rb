# frozen_string_literal: true

require "pcs"
require "pcs/cli"
require "tmpdir"

Dir[File.join(__dir__, "support", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  # Every example gets its own empty data directory.
  config.around do |example|
    Dir.mktmpdir do |dir|
      FlatRecord.configure { |c| c.data_path = File.join(dir, "data") }
      @tmpdir = Pathname.new(dir)
      example.run
    ensure
      FlatRecord.configure { |c| c.data_path = "data" }
    end
  end
end
