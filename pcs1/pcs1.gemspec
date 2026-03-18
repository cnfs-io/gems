# frozen_string_literal: true

require_relative "lib/pcs1/version"

Gem::Specification.new do |spec|
  spec.name = "pcs1"
  spec.version = Pcs1::VERSION
  spec.authors = ["Robert Roach"]
  spec.email = ["rjayroach@gmail.com"]

  spec.summary = "PCS private cloud infrastructure CLI"
  spec.description = "Interactive CLI for bootstrapping and managing bare-metal private cloud sites"
  spec.homepage = "TODO: Put your gem's website or public repo URL here."
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rest_cli"
  spec.add_dependency "flat_record"
  spec.add_dependency "net-ssh", "~> 7.0"
  spec.add_dependency "ed25519", "~> 1.2"
  spec.add_dependency "bcrypt_pbkdf", "~> 1.0"
  spec.add_dependency "state_machines-activemodel"
end
