---
---

# Plan 04: Namespace Consolidation, Unified Config, and Console

## Context

Read these files before starting:

- `lib/pim.rb` — `Pim::Config`, `Pim::Profile`, `Pim::Server` (main module)
- `lib/pim/config.rb` — `PimConfig` module (nearly empty after plan-03)
- `lib/pim/profile.rb` — `PimProfile::Config`, `PimProfile::Manager`
- `lib/pim/iso.rb` — `PimIso::Config`, `PimIso::Manager`
- `lib/pim/build.rb` — `PimBuild::Config`, `PimBuild::ArchitectureResolver`, `PimBuild::CacheManager`, `PimBuild::ScriptLoader`
- `lib/pim/build/local_builder.rb` — `PimBuild::LocalBuilder`
- `lib/pim/build/manager.rb` — `PimBuild::Manager`
- `lib/pim/registry.rb` — `PimRegistry::Registry`
- `lib/pim/ventoy.rb` — `PimVentoy::Config`, `PimVentoy::Manager`
- `lib/pim/qemu.rb` — `PimQemu::DiskImage`, `PimQemu::CommandBuilder`, `PimQemu::VM`, plus module methods
- `lib/pim/ssh.rb` — `PimSSH::Connection`
- `lib/pim/cli.rb` — Dry::CLI registry
- `lib/pim/commands/**/*.rb` — all command files (check for `exit 1` calls and domain class references)
- `lib/pim/project.rb` — `Pim::Project`

## Objective

Three changes delivered together as one coherent refactor:

1. **Namespace consolidation** — flatten all classes under `Pim::` so everything is one level deep
2. **Unified Config** — `Pim::Config` reads `pim.yml` once, exposes sub-configs via accessors
3. **Console** — `pim console` / `pim c` starts `Pry.start(Pim)` with a CLI dispatch helper

## Part 1: Namespace consolidation

### Design principle

Everything is `Pim::DescriptiveName` — flat, no nested modules. In a Pry REPL on `Pim`, you type `ProfileConfig` not `Profile::Config`. No class/module collisions. Every name is self-explanatory.

### Rename map

| Current | New |
|---------|-----|
| `Pim::Config` | `Pim::Config` (unchanged) |
| `Pim::Profile` | `Pim::Profile` (unchanged — the model) |
| `Pim::Project` | `Pim::Project` (unchanged) |
| `Pim::Server` | `Pim::Server` (unchanged) |
| `PimProfile::Config` | `Pim::ProfileConfig` |
| `PimProfile::Manager` | `Pim::ProfileManager` |
| `PimIso::Config` | `Pim::IsoConfig` |
| `PimIso::Manager` | `Pim::IsoManager` |
| `PimBuild::Config` | `Pim::BuildConfig` |
| `PimBuild::ArchitectureResolver` | `Pim::ArchitectureResolver` |
| `PimBuild::CacheManager` | `Pim::CacheManager` |
| `PimBuild::ScriptLoader` | `Pim::ScriptLoader` |
| `PimBuild::LocalBuilder` | `Pim::LocalBuilder` |
| `PimBuild::Manager` | `Pim::BuildManager` |
| `PimRegistry::Registry` | `Pim::Registry` |
| `PimVentoy::Config` | `Pim::VentoyConfig` |
| `PimVentoy::Manager` | `Pim::VentoyManager` |
| `PimQemu::DiskImage` | `Pim::QemuDiskImage` |
| `PimQemu::CommandBuilder` | `Pim::QemuCommandBuilder` |
| `PimQemu::VM` | `Pim::QemuVM` |
| `PimQemu` module methods (e.g., `find_available_port`) | `Pim::Qemu.find_available_port` (keep as a utility module) |
| `PimSSH::Connection` | `Pim::SSHConnection` |
| `PimConfig` | removed (empty module) |

### XDG constants

Define once on `Pim`:

```ruby
module Pim
  XDG_CONFIG_HOME = ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config'))
  XDG_DATA_HOME = ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share'))
  XDG_CACHE_HOME = ENV.fetch('XDG_CACHE_HOME', File.expand_path('~/.cache'))
end
```

Remove `XDG_*` constants from all other files. Reference as `Pim::XDG_CACHE_HOME` etc.

### File layout after rename

The file layout stays the same — files don't need to move. Just the module/class declarations inside them change:

- `lib/pim/profile.rb` — contains `Pim::ProfileConfig` and `Pim::ProfileManager`
- `lib/pim/iso.rb` — contains `Pim::IsoConfig` and `Pim::IsoManager`
- `lib/pim/build.rb` — contains `Pim::BuildConfig`, `Pim::ArchitectureResolver`, `Pim::CacheManager`, `Pim::ScriptLoader`
- `lib/pim/build/local_builder.rb` — contains `Pim::LocalBuilder`
- `lib/pim/build/manager.rb` — contains `Pim::BuildManager`
- `lib/pim/registry.rb` — contains `Pim::Registry`
- `lib/pim/ventoy.rb` — contains `Pim::VentoyConfig` and `Pim::VentoyManager`
- `lib/pim/qemu.rb` — contains `Pim::Qemu` (utility module), `Pim::QemuDiskImage`, `Pim::QemuCommandBuilder`, `Pim::QemuVM`
- `lib/pim/ssh.rb` — contains `Pim::SSHConnection`

### Implementation approach

1. Update module/class declarations in each domain file
2. Update all internal cross-references (e.g., `PimBuild::Config.new` → `Pim::BuildConfig.new`)
3. Update all command files in `lib/pim/commands/`
4. Update `lib/pim.rb` — move `Pim::Profile` and `Pim::Config` class definitions, add XDG constants
5. Update all specs to use new names
6. Delete `lib/pim/config.rb` if it's just an empty `PimConfig` module
7. Run specs

## Part 2: Unified Config

### Current problem

Four classes independently read and parse `pim.yml`:

- `Pim::Config` — reads `pim.yml`
- `PimBuild::Config` (→ `Pim::BuildConfig`) — reads `pim.yml` again
- `PimIso::Config` (→ `Pim::IsoConfig`) — reads `pim.yml` again
- `PimVentoy::Config` (→ `Pim::VentoyConfig`) — reads `pim.yml` again

### New design

`Pim::Config` reads `pim.yml` once and passes relevant sections to sub-configs:

```ruby
module Pim
  class Config
    attr_reader :runtime_config

    def initialize(project_dir: nil)
      @project_dir = project_dir || Pim::Project.root!
      @runtime_config = load_runtime_config
    end

    def project_dir = @project_dir

    # Sub-config accessors (lazy-loaded, memoized)
    def build
      @build ||= Pim::BuildConfig.new(
        runtime_config: @runtime_config,
        project_dir: @project_dir
      )
    end

    def iso
      @iso ||= Pim::IsoConfig.new(
        runtime_config: @runtime_config,
        project_dir: @project_dir
      )
    end

    def profiles
      @profiles ||= Pim::ProfileConfig.new(project_dir: @project_dir)
    end

    def ventoy
      @ventoy ||= Pim::VentoyConfig.new(
        runtime_config: @runtime_config,
        project_dir: @project_dir
      )
    end

    def serve_defaults
      @runtime_config['serve'] || {}
    end

    # Convenience delegations
    def profile(name) = profiles.profile(name)
    def profile_names = profiles.profile_names

    private

    def load_runtime_config
      project_file = File.join(@project_dir, 'pim.yml')
      load_yaml(project_file)
    end

    def load_yaml(path)
      return {} unless File.exist?(path)
      YAML.load_file(path) || {}
    rescue Psych::SyntaxError => e
      warn "Warning: Failed to parse #{path}: #{e.message}"
      {}
    end
  end
end
```

### Sub-config changes

Each sub-config changes its initializer to accept the already-parsed config:

**`Pim::BuildConfig`:**

```ruby
def initialize(runtime_config: {}, project_dir: Dir.pwd)
  @project_dir = project_dir
  @build_config = DEFAULT_BUILD_CONFIG.dup.deep_merge(runtime_config['build'] || {})
end
```

Remove `load_runtime_config` and `load_yaml`.

**`Pim::IsoConfig`:**

```ruby
def initialize(runtime_config: {}, project_dir: Dir.pwd)
  @project_dir = project_dir
  @runtime_config = runtime_config
  @isos = load_isos  # still reads isos.d/ files
end
```

Remove `load_runtime_config`. Keep `load_isos` (reads `.d/` directory, not `pim.yml`).

**`Pim::VentoyConfig`:**

```ruby
def initialize(runtime_config: {}, project_dir: Dir.pwd)
  @project_dir = project_dir
  @ventoy_section = runtime_config['ventoy'] || {}
end
```

Remove `load_runtime_config` and `load_yaml`. Update all accessors to read from `@ventoy_section`.

**`Pim::ProfileConfig`:** No change needed — reads `profiles.d/*.yml` only, not `pim.yml`.

### Manager classes

Managers should accept either their specific sub-config or the unified Config. Update to accept `config:` as a required keyword:

```ruby
# In a command:
config = Pim::Config.new
manager = Pim::IsoManager.new(config: config.iso)
manager = Pim::ProfileManager.new(config: config.profiles)
manager = Pim::BuildManager.new(config: config)  # needs full config
```

For `BuildManager` and `LocalBuilder` that need access to multiple sub-configs (build settings + profiles + ISOs), pass the top-level `Pim::Config`.

## Part 3: Console

### `Pim.exit!` — context-aware exit

Add to `lib/pim.rb`:

```ruby
module Pim
  class CommandError < StandardError; end

  @console_mode = false

  def self.console_mode!
    @console_mode = true
  end

  def self.console_mode?
    @console_mode == true
  end

  def self.exit!(code = 1, message: nil)
    $stderr.puts(message) if message
    if console_mode?
      raise CommandError, message || "command failed (exit #{code})"
    else
      Kernel.exit(code)
    end
  end
end
```

Replace all `exit 1` in `lib/` with `Pim.exit!(1, message: "...")`. Search for:

- `exit 1` in `lib/pim/commands/**/*.rb`
- `exit 1` in `lib/pim/*.rb`
- `exit 130` in `lib/pim/build/local_builder.rb`

### `Pim.run` — CLI dispatch helper

```ruby
module Pim
  def self.run(*args)
    Dry::CLI.new(Pim::CLI).call(arguments: args.flat_map { |a| a.split(" ") })
  rescue CommandError => e
    $stderr.puts e.message
  end
end
```

### `pim console` command

Create `lib/pim/commands/console.rb`:

```ruby
# frozen_string_literal: true

require "dry/cli"

module Pim
  module Commands
    class Console < Dry::CLI::Command
      desc "Start an interactive console with project context loaded"

      def call(**)
        require "pry"
        Pim.console_mode!
        Pry.start(Pim)
      end
    end
  end
end
```

### Register in CLI

In `lib/pim/cli.rb`:

```ruby
require_relative "commands/console"

register "console", Commands::Console
register "c",       Commands::Console
```

### Add dependency

In `pim.gemspec`:

```ruby
spec.add_dependency "pry", "~> 0.14"
```

## Console usage examples

```ruby
$ cd myproject
$ pim c

pim> c = Config.new
pim> c.build.memory          #=> 2048
pim> c.build.image_dir       #=> #<Pathname:...>
pim> c.profiles.profile_names #=> ["default"]
pim> c.profile("default")    #=> {"hostname"=>"pim", ...}
pim> c.iso.isos.keys         #=> ["debian-13.3.0"]

pim> r = Registry.new(image_dir: c.build.image_dir)
pim> r.list

pim> Pim.run "profile list"
pim> Pim.run "build status"
pim> Pim.run "iso list -l"

pim> exit
```

## Test spec

### `spec/pim/config_spec.rb` (rewrite)

Test unified `Pim::Config`:

- Reads `pim.yml` from project directory
- Exposes `runtime_config` hash
- `config.build` returns a `Pim::BuildConfig` instance
- `config.iso` returns a `Pim::IsoConfig` instance
- `config.profiles` returns a `Pim::ProfileConfig` instance
- `config.ventoy` returns a `Pim::VentoyConfig` instance
- Sub-configs are memoized (same object on repeated access)
- `config.profile("default")` delegates to profiles
- `config.profile_names` delegates to profiles
- `config.serve_defaults` returns serve section or empty hash
- Handles missing `pim.yml` gracefully

### `spec/pim/build_config_spec.rb` (update)

- Accepts `runtime_config:` hash instead of reading `pim.yml`
- Applies defaults when no `build` section present
- Deep merges runtime `build` section over defaults

### `spec/pim/iso_config_spec.rb` (update)

- Accepts `runtime_config:` hash
- Still loads `isos.d/*.yml` from project directory

### `spec/pim/ventoy_config_spec.rb` (update)

- Accepts `runtime_config:` hash

### `spec/pim/console_spec.rb` (new)

- `Pim.console_mode!` sets console mode
- `Pim.console_mode?` returns true after activation
- `Pim.exit!` calls `Kernel.exit` in normal mode
- `Pim.exit!` raises `Pim::CommandError` in console mode
- `Pim.exit!` includes message in both modes
- `Pim.run` dispatches to Dry::CLI (mock or capture stdout)
- `Pim.run` rescues `CommandError` and prints to stderr

### `spec/pim/namespace_spec.rb` (new)

```ruby
RSpec.describe "Pim namespace" do
  it "has all domain classes at top level" do
    %w[
      Config Profile Project Server Registry CommandError
      ProfileConfig ProfileManager
      IsoConfig IsoManager
      BuildConfig BuildManager LocalBuilder
      ArchitectureResolver CacheManager ScriptLoader
      VentoyConfig VentoyManager
      QemuDiskImage QemuCommandBuilder QemuVM
      SSHConnection
    ].each do |klass|
      expect(defined?(Pim.const_get(klass))).to eq("constant"),
        "Expected Pim::#{klass} to be defined"
    end
  end
end
```

### Update all existing specs

Mechanical find-and-replace of old names to new names across all spec files.

## Verification

```bash
# All specs pass
bundle exec rspec

# No old namespace references remain
grep -rn "PimProfile" lib/ spec/    # should return nothing
grep -rn "PimIso" lib/ spec/        # should return nothing
grep -rn "PimBuild" lib/ spec/      # should return nothing
grep -rn "PimRegistry" lib/ spec/   # should return nothing
grep -rn "PimVentoy" lib/ spec/     # should return nothing
grep -rn "PimConfig" lib/ spec/     # should return nothing
grep -rn "PimQemu" lib/ spec/       # should return nothing
grep -rn "PimSSH" lib/ spec/        # should return nothing

# No exit 1 calls remain in lib/
grep -rn "exit 1" lib/              # should return nothing
grep -rn "exit 130" lib/            # should return nothing

# Config reads pim.yml only once
grep -rn "load_runtime_config" lib/ # should only be in Pim::Config

# Console works (manual)
cd /path/to/pim/project
pim c
pim> Config.new
pim> ProfileConfig.new(project_dir: ".")
pim> Pim.run "profile list"
pim> exit
```
