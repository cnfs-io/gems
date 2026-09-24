# frozen_string_literal: true

require "pcs1"
require_relative "support/test_project"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Create a fresh temp project for each test
  config.around do |example|
    Dir.mktmpdir("pcs1_test") do |tmpdir|
      @test_dir = tmpdir
      TestProject.create(tmpdir)

      # Point Pcs1.root at the temp project via instance variable
      Pcs1.reset!
      Pcs1.instance_variable_set(:@root, Pathname.new(tmpdir))

      # Configure FlatRecord to use temp data dir
      data_dir = File.join(tmpdir, "data")
      FlatRecord.configure { |c| c.data_path = data_dir }

      # Reload all model stores
      [Pcs1::Site, Pcs1::Host, Pcs1::Network, Pcs1::Interface].each do |model|
        model.reload! if model.respond_to?(:reload!)
      end

      # Silence logger
      Pcs1.logger = Logger.new(File::NULL)

      example.run
    end
  end

  # Prevent real shell commands and SSH
  config.before do
    allow(Pcs1::Platform).to receive(:system_cmd)
    allow(Pcs1::Platform).to receive(:sudo_write)
    allow(Pcs1::Platform).to receive(:capture).and_return("")
    allow(Pcs1::Platform).to receive(:command_exists?).and_return(true)
    allow(Net::SSH).to receive(:start)
  end
end

module TestHelpers
  def test_dir
    @test_dir
  end

  def data_dir
    File.join(test_dir, "data")
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
