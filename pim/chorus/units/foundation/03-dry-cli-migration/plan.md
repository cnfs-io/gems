---
---

# Plan 03: Migrate from Thor to Dry::CLI

## Context

Read these files before starting:

- `lib/pim.rb` — `Pim::CLI < Thor` with subcommand registration, `Pim::Server`
- `lib/pim/config.rb` — `PimConfig::CLI < Thor` (config list/get/set)
- `lib/pim/profile.rb` — `PimProfile::CLI < Thor` (profile list/show/add)
- `lib/pim/iso.rb` — `PimIso::CLI < Thor` (iso list/download/verify/config)
- `lib/pim/build.rb` — `PimBuild::CLI < Thor` (build run/list/show/clean/status)
- `lib/pim/ventoy.rb` — `PimVentoy::CLI < Thor` (ventoy subcommands)
- `exe/pim` — entrypoint: `Pim::CLI.start(ARGV)`
- `pim.gemspec` — currently depends on `thor ~> 1.0`

Reference implementations (dry-cli pattern):

- `~/.local/share/ppm/gems/pcs/lib/pcs/cli.rb` — registry with `register "command subcommand", Commands::Class`
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/site.rb` — namespace command (prints usage)
- `~/.local/share/ppm/gems/pcs/lib/pcs/commands/site/add.rb` — subcommand with arguments and options
- `~/.local/share/ppm/gems/pcs/exe/pcs` — entrypoint: `Dry::CLI.new(Pcs::CLI).call`

## Objective

Replace Thor with Dry::CLI for the command-line interface. This aligns PIM with the other gems (pcs, chorus, opcred) and produces a cleaner file layout where each command is its own file under `lib/pim/commands/`.

## Design decisions

### File layout

Thor puts all subcommands for a group in one file (e.g., all build commands in `build.rb`). Dry::CLI uses one file per command:

```
lib/pim/commands/
├── new.rb                    # pim new
├── serve.rb                  # pim serve
├── verify.rb                 # pim verify
├── version.rb                # pim version
├── config.rb                 # pim config (namespace)
├── config/
│   ├── list.rb               # pim config list
│   ├── get.rb                # pim config get
│   └── set.rb                # pim config set
├── iso.rb                    # pim iso (namespace)
├── iso/
│   ├── list.rb               # pim iso list
│   ├── download.rb           # pim iso download
│   ├── verify.rb             # pim iso verify
│   └── config.rb             # pim iso config
├── profile.rb                # pim profile (namespace)
├── profile/
│   ├── list.rb               # pim profile list
│   ├── show.rb               # pim profile show
│   └── add.rb                # pim profile add
├── build.rb                  # pim build (namespace)
├── build/
│   ├── run.rb                # pim build run
│   ├── list.rb               # pim build list
│   ├── show.rb               # pim build show
│   ├── clean.rb              # pim build clean
│   └── status.rb             # pim build status
└── ventoy.rb                 # pim ventoy (namespace, expand later)
```

### Registry pattern

The central registry in `lib/pim/cli.rb` maps command strings to command classes:

```ruby
module Pim
  module CLI
    extend Dry::CLI::Registry

    register "version",      Commands::Version
    register "new",          Commands::New
    register "serve",        Commands::Serve
    register "verify",       Commands::Verify

    register "config",       Commands::Config
    register "config list",  Commands::Config::List
    register "config get",   Commands::Config::Get
    register "config set",   Commands::Config::Set

    register "iso",          Commands::Iso
    register "iso list",     Commands::Iso::List
    # ... etc
  end
end
```

### Business logic stays in domain classes

Commands are thin — they parse arguments, instantiate domain objects, and call methods. The existing domain classes (`Pim::Config`, `PimProfile::Manager`, `PimIso::Manager`, `PimBuild::Manager`, etc.) keep their logic. The migration only replaces the CLI layer.

For example, the current `PimProfile::CLI#list` calls `manager.list(long: options[:long])`. The new `Commands::Profile::List#call` does the same thing — it just uses dry-cli argument/option syntax instead of Thor's.

### Thor-isms to translate

| Thor | Dry::CLI |
|------|----------|
| `desc 'name', 'description'` | `desc "description"` |
| `option :foo, type: :boolean` | `option :foo, type: :boolean` |
| `argument` (positional in method sig) | `argument :name, required: true` |
| `def self.exit_on_failure? = true` | Not needed (dry-cli handles this) |
| `map 'ls' => :list` | `register "build ls", Commands::Build::List` (alias via registration) |
| `subcommand 'build', PimBuild::CLI` | `register "build run", Commands::Build::Run` (flat registration) |

### Aliases

Thor's `map 'ls' => :list` becomes a second registration:

```ruby
register "build list", Commands::Build::List
register "build ls",   Commands::Build::List
```

### Namespace commands

When a user runs `pim build` without a subcommand, Thor shows help. With dry-cli, register a namespace command that prints usage:

```ruby
module Pim
  module Commands
    class Build < Dry::CLI::Command
      desc "Build VM images"
      def call(*) = puts "Usage: pim build [run|list|show|clean|status]"
    end
  end
end
```

## Implementation

### 1. Update dependencies

In `pim.gemspec`:

- Remove: `spec.add_dependency "thor", "~> 1.0"`
- Add: `spec.add_dependency "dry-cli", "~> 1.0"`

### 2. Create the CLI registry

Create `lib/pim/cli.rb` with the full registry. This file requires all command files and registers them.

### 3. Create command files

For each Thor action, create a corresponding dry-cli command class. The command class:

- Inherits from `Dry::CLI::Command`
- Declares `desc`, `argument`, and `option`
- Implements `def call(**options)` that delegates to the existing domain class

Work through each command group systematically:

**a) Top-level commands:**
- `pim new` — from plan-02's `Pim::Project`
- `pim serve` — from `Pim::Server` (instantiate config, profile, server, start)
- `pim verify` — from plan-04's `Pim::Verifier`
- `pim version` — inline, just prints version

**b) Config commands:**
- `pim config list` — from `PimConfig::CLI#list`
- `pim config get KEY` — from `PimConfig::CLI#get`
- `pim config set KEY VALUE` — from `PimConfig::CLI#set`

**c) ISO commands:**
- `pim iso list` — from `PimIso::CLI#list`
- `pim iso download KEY` — from `PimIso::CLI#download`
- `pim iso verify KEY` — from `PimIso::CLI#verify`
- `pim iso config` — from `PimIso::CLI#config` (if it exists)

**d) Profile commands:**
- `pim profile list` — from `PimProfile::CLI#list`
- `pim profile show NAME` — from `PimProfile::CLI#show`
- `pim profile add` — from `PimProfile::CLI#add`

**e) Build commands:**
- `pim build run PROFILE` — from `PimBuild::CLI#run_build`
- `pim build list` — from `PimBuild::CLI#list`
- `pim build show PROFILE` — from `PimBuild::CLI#show`
- `pim build clean` — from `PimBuild::CLI#clean`
- `pim build status` — from `PimBuild::CLI#status`

**f) Ventoy commands:**
- Read `lib/pim/ventoy.rb` to determine which subcommands exist, then create corresponding command files.

### 4. Update entrypoint

Change `exe/pim`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "pim"

Dry::CLI.new(Pim::CLI).call
```

### 5. Update `lib/pim.rb`

- Remove `require "thor"` 
- Remove `Pim::CLI < Thor` class entirely
- Add `require_relative "pim/cli"` 
- Keep all domain classes (`Pim::Config`, `Pim::Profile`, `Pim::Server`, etc.) unchanged

### 6. Remove Thor from domain files

The domain files (`config.rb`, `profile.rb`, `iso.rb`, `build.rb`, `ventoy.rb`) currently contain both domain logic and Thor CLI classes in the same file. After migration:

- Remove the `CLI < Thor` class from each domain file
- Keep the domain classes (`Config`, `Manager`, etc.) in place
- The CLI classes now live in `lib/pim/commands/`

For example, `lib/pim/profile.rb` currently contains `PimProfile::Config`, `PimProfile::Manager`, and `PimProfile::CLI`. After this plan, it contains only `PimProfile::Config` and `PimProfile::Manager`. The CLI is now `Pim::Commands::Profile::List`, `Pim::Commands::Profile::Show`, etc.

### 7. Clean up module namespacing

The current code uses mixed namespacing: `PimConfig`, `PimProfile`, `PimIso`, `PimBuild`. Consider whether to consolidate under `Pim::` namespace (e.g., `Pim::Profile::Config` instead of `PimProfile::Config`). This is optional for this plan — the priority is the CLI migration. If the renaming is straightforward, do it. If it creates cascading changes, defer to a separate plan.

## Test spec

### `spec/pim/commands/` (new specs)

For each command, test that:

- It exists and is registered in the CLI
- Arguments and options are declared correctly
- `call` delegates to the correct domain class with correct arguments

These should be **lightweight** — mock the domain classes and verify the command wires them up correctly. The domain logic is already tested in plan-01 specs.

Example:

```ruby
# spec/pim/commands/profile/list_spec.rb
RSpec.describe Pim::Commands::Profile::List do
  it "delegates to PimProfile::Manager#list" do
    manager = instance_double(PimProfile::Manager)
    allow(PimProfile::Manager).to receive(:new).and_return(manager)
    expect(manager).to receive(:list).with(long: false)

    subject.call(long: false)
  end
end
```

### Update existing specs

Existing specs from plan-01 that test domain classes should continue to pass unchanged — this plan only replaces the CLI layer, not the domain logic.

### CLI integration smoke tests

Add a few specs that invoke the CLI end-to-end (using `Dry::CLI.new(Pim::CLI)` with captured stdout) to verify command routing:

```ruby
# spec/pim/cli_spec.rb
RSpec.describe Pim::CLI do
  it "routes 'version' to version command" do
    expect { Dry::CLI.new(described_class).call(arguments: ["version"]) }
      .to output(/pim \d/).to_stdout
  end

  it "routes 'profile list' to profile list command" do
    # within a scaffolded project dir
    expect { Dry::CLI.new(described_class).call(arguments: ["profile", "list"]) }
      .not_to raise_error
  end
end
```

## Verification

```bash
# All specs pass
bundle exec rspec

# No Thor references remain
grep -r "thor" lib/         # should return nothing
grep -r "Thor" lib/         # should return nothing
grep -r "thor" pim.gemspec  # should return nothing

# CLI works
pim version
pim new /tmp/pim-test
cd /tmp/pim-test
pim profile list
pim config list
pim iso list
pim build status

# Aliases work
pim profile ls              # same as pim profile list
pim build ls                # same as pim build list
pim config ls               # same as pim config list

# Clean up
rm -rf /tmp/pim-test
```
