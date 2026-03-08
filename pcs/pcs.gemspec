# frozen_string_literal: true

require_relative "lib/pcs/version"

Gem::Specification.new do |spec|
  spec.name = "pcs"
  spec.version = Pcs::VERSION
  spec.authors = ["Roberto Roach"]
  spec.summary = "PCS private cloud infrastructure CLI"
  spec.description = "Interactive CLI for bootstrapping and managing bare-metal private cloud sites"
  spec.homepage = "https://github.com/rjayroach/gems"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,exe}/**/*", "*.gemspec", "README.md"].reject { |f| f.start_with?("spec/", "test/") }
  end

  spec.bindir = "exe"
  spec.executables = ["pcs"]

  spec.add_dependency "dry-cli", "~> 1.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "net-ssh", "~> 7.0"
  spec.add_dependency "ed25519", "~> 1.2"
  spec.add_dependency "bcrypt_pbkdf", "~> 1.0"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "dotenv", "~> 3.0"
  spec.add_dependency "ostruct"
  spec.add_dependency "rexml"
  spec.add_dependency "flat_record"
  spec.add_dependency "rest_cli"

  spec.add_development_dependency "rspec", "~> 3.0"
end
