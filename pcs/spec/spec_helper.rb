# frozen_string_literal: true

require "pcs"
require "fileutils"
require "tmpdir"

FIXTURES_DIR = Pathname.new(__dir__) / "fixtures" / "project"

RSpec.shared_context "fixture project" do
  around(:each) do |example|
    Dir.mktmpdir("pcs-test-") do |tmpdir|
      root = Pathname.new(tmpdir)
      FileUtils.cp_r(FIXTURES_DIR.children, root)
      Dir.chdir(root) do
        ENV.delete("PCS_SITE")
        Pcs.boot!(project_dir: root)
        example.run
      ensure
        Pcs.reset!
      end
    end
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.order = :random

  config.include_context "fixture project", :uses_fixture_project
end
