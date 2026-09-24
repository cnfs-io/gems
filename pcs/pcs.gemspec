# frozen_string_literal: true

require_relative "lib/pcs/version"

Gem::Specification.new do |spec|
  spec.name = "pcs"
  spec.version = Pcs::VERSION
  spec.authors = ["Robert Roach"]
  spec.email = ["rjayroach@gmail.com"]

  spec.summary = "PCS private cloud infrastructure CLI"
  spec.description = "Takes a site's bare-metal machines from on-the-network to installed, from a control plane"
  spec.homepage = "https://github.com/rjayroach/gems"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
  spec.add_dependency "bcrypt_pbkdf", "~> 1.0" # encrypted OpenSSH keys for net-ssh
  spec.add_dependency "ed25519", "~> 1.2" # ed25519 keys for net-ssh
  spec.add_dependency "flat_record"
  spec.add_dependency "net-ssh", "~> 7.0"
  spec.add_dependency "phlex"
  spec.add_dependency "rexml" # nmap's XML output
  spec.add_dependency "roda"
  spec.add_dependency "ruby_ui"
  spec.add_dependency "state_machines-activemodel"
  spec.add_dependency "termino"
end
