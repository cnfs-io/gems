# frozen_string_literal: true

require_relative "lib/pim/version"

Gem::Specification.new do |spec|
  spec.name = "pim"
  spec.version = Pim::VERSION
  spec.authors = ["Roberto Roach"]
  spec.summary = "Product Image Manager"
  spec.description = "A CLI tool for building, managing, and deploying VM images using QEMU"
  spec.homepage = "https://github.com/rjayroach/gems"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,exe}/**/*", "*.gemspec", "README.md", "docs/**/*"].reject { |f| f.start_with?("spec/", "test/") }
  end

  spec.bindir = "exe"
  spec.executables = ["pim"]

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "dry-cli", "~> 1.0"
  spec.add_dependency "webrick", "~> 1.9"
  spec.add_dependency "net-ssh", "~> 7.0"
  spec.add_dependency "net-scp", "~> 4.0"
  spec.add_dependency "pry", "~> 0.14"
  spec.add_dependency "flat_record"

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-mocks", "~> 3.0"
end
