---
---

# Plan 03 — Command Consolidation

## Objective

Restructure all PIM commands into the single-file-per-resource convention. Each resource gets one `*_command.rb` file containing a class that inherits from `RestCli::Command` with inner classes for each action. CRUD-like actions (list, show) use the view layer; domain-specific action commands keep their existing logic. Standalone commands (new, console, serve, version) remain as individual files. The `verify` command moves into `BuildsCommand` since it operates on build recipes.

This is the largest plan in the refactor tier. It touches every command file and the CLI registry.

## Context

Read before starting:
- `lib/pim/cli.rb` — current CLI registry (will be rewritten)
- `lib/pim/views/` — all view files (from plans 01–02)
- All files in `lib/pim/commands/` — current command implementations
- `lib/rest_cli/command.rb` — RestCli::Command base class
- `lib/rest_cli/concern/standard_flags.rb` — StandardFlags mixin (included by RestCli::Command)

## Implementation Spec

### Strategy

For each resource, create a single `*_command.rb` file that:
1. Defines an outer class inheriting from `RestCli::Command`
2. Contains inner classes for each action, inheriting from `self`
3. CRUD actions (List, Show) use the view layer
4. Action commands preserve their existing logic but move into inner classes
5. Placeholder commands (Add with "not yet implemented") are preserved as-is

### Resource command files to create

#### `lib/pim/commands/profiles_command.rb`

Consolidates: `commands/profile.rb`, `commands/profile/get.rb`, `commands/profile/add.rb`

Current `profile get` is a combined list/show command. Split into proper `List` and `Show` inner classes.

```ruby
# frozen_string_literal: true

module Pim
  class ProfilesCommand < RestCli::Command
    class List < self
      desc "List all profiles"

      def call(**options)
        view.list(Pim::Profile.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show profile information"

      argument :id, required: true, desc: "Profile name"

      def call(id:, **options)
        profile = Pim::Profile.find(id)
        view.show(profile, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Profile '#{id}' not found")
      end
    end

    class Add < self
      desc "Add a new profile"

      def call(**)
        puts "Profile add requires write support (not yet available with read-only FlatRecord)."
        puts "Manually add entries to profiles.yml in your project directory."
      end
    end
  end
end
```

#### `lib/pim/commands/isos_command.rb`

Consolidates: `commands/iso.rb`, `commands/iso/get.rb`, `commands/iso/download.rb`, `commands/iso/verify.rb`, `commands/iso/add.rb`

```ruby
# frozen_string_literal: true

module Pim
  class IsosCommand < RestCli::Command
    class List < self
      desc "List all ISOs in catalog"

      def call(**options)
        view.list(Pim::Iso.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show ISO information"

      argument :id, required: true, desc: "ISO key"

      def call(id:, **options)
        iso = Pim::Iso.find(id)
        view.show(iso, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: ISO '#{id}' not found")
      end
    end

    class Download < self
      desc "Download a specific ISO from catalog"

      argument :iso_key, required: false, desc: "ISO key to download"

      option :all, type: :boolean, default: false, aliases: ["-a"], desc: "Download all missing ISOs"

      def call(iso_key: nil, all: false, **)
        if all
          download_all
        elsif iso_key
          iso = Pim::Iso.find(iso_key)
          iso.download
        else
          puts "Error: Provide an ISO key or use --all flag"
          Pim.exit!(1)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: ISO '#{iso_key}' not found in catalog")
      end

      private

      def download_all
        isos = Pim::Iso.all
        missing = isos.reject(&:downloaded?)

        if missing.empty?
          puts "All ISOs are already downloaded."
          return
        end

        puts "Downloading missing ISOs...\n\n"
        success_count = 0
        missing.each_with_index do |iso, idx|
          puts "[#{idx + 1}/#{missing.size}] Downloading #{iso.id}..."
          Pim::HTTP.download(iso.url, iso.iso_path.to_s)
          if iso.verify(silent: true)
            puts "OK Downloaded and verified\n\n"
            success_count += 1
          else
            puts "FAIL Checksum verification failed\n\n"
          end
        end
        puts "Summary: #{success_count} ISOs downloaded successfully"
      end
    end

    class Verify < self
      desc "Verify checksum of a downloaded ISO"

      argument :iso_key, required: false, desc: "ISO key to verify"

      option :all, type: :boolean, default: false, aliases: ["-a"], desc: "Verify all downloaded ISOs"

      def call(iso_key: nil, all: false, **)
        if all
          verify_all
        elsif iso_key
          iso = Pim::Iso.find(iso_key)
          iso.verify
        else
          puts "Error: Provide an ISO key or use --all flag"
          Pim.exit!(1)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: ISO '#{iso_key}' not found in catalog")
      end

      private

      def verify_all
        isos = Pim::Iso.all
        downloaded = isos.select(&:downloaded?)

        if downloaded.empty?
          puts "No downloaded ISOs to verify."
          return
        end

        puts "Verifying downloaded ISOs...\n\n"
        passed = 0
        failed = 0
        downloaded.each do |iso|
          result = iso.verify(silent: true)
          fname = iso.filename || "#{iso.id}.iso"
          status = result ? "OK" : "FAIL Checksum mismatch"
          puts "#{fname.ljust(35)} #{status}"
          result ? passed += 1 : failed += 1
        end
        puts
        puts "Summary: #{passed} passed, #{failed} failed"
      end
    end

    class Add < self
      desc "Add a new ISO to the catalog interactively"

      def call(**)
        puts "ISO add requires write support (not yet available with read-only FlatRecord)."
        puts "Manually add entries to isos.yml in your project directory."
      end
    end
  end
end
```

#### `lib/pim/commands/builds_command.rb`

Consolidates: `commands/build.rb`, `commands/build/get.rb`, `commands/build/run.rb`, `commands/build/clean.rb`, `commands/build/status.rb`, `commands/verify.rb`

```ruby
# frozen_string_literal: true

module Pim
  class BuildsCommand < RestCli::Command
    class List < self
      desc "List build recipes"

      def call(**options)
        view.list(Pim::Build.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show build recipe information"

      argument :id, required: true, desc: "Build recipe ID"

      def call(id:, **options)
        build = Pim::Build.find(id)
        view.show(build, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Build '#{id}' not found")
      end
    end

    class Run < self
      desc "Build an image from a build recipe"

      argument :build_id, required: true, desc: "Build recipe ID"

      option :force, type: :boolean, default: false, aliases: ["-f"], desc: "Force rebuild ignoring cache"
      option :dry_run, type: :boolean, default: false, aliases: ["-n"], desc: "Show what would be done"
      option :vnc, type: :integer, default: nil, desc: "Enable VNC display on port 5900+N"
      option :console, type: :boolean, default: false, aliases: ["-c"], desc: "Stream serial console output to stdout"
      option :console_log, type: :string, default: nil, desc: "Log serial console to file"

      def call(build_id:, force: false, dry_run: false, vnc: nil, console: false, console_log: nil, **)
        require_relative "../build/manager"

        build = Pim::Build.find(build_id)
        manager = Pim::BuildManager.new

        if dry_run
          manager.dry_run_build(build)
        else
          manager.execute_build(
            build,
            force: force,
            vnc: vnc,
            console: console,
            console_log: console_log
          )
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Build '#{build_id}' not found")
      end
    end

    class Clean < self
      desc "Clean cached images"

      option :orphaned, type: :boolean, default: false, desc: "Only remove orphaned registry entries"
      option :all, type: :boolean, default: false, desc: "Remove all cached images"

      def call(orphaned: false, all: false, **)
        config = Pim::BuildConfig.new
        registry = Pim::Registry.new(image_dir: config.image_dir)

        if orphaned
          removed = registry.clean_orphaned
          if removed.empty?
            puts "No orphaned entries found"
          else
            puts "Removed #{removed.size} orphaned entries:"
            removed.each { |key| puts "  - #{key}" }
          end
        elsif all
          print "Remove all images in #{config.image_dir}? (y/N) "
          response = $stdin.gets.chomp
          return unless response.downcase == "y"

          entries = registry.list
          entries.each do |entry|
            FileUtils.rm_f(entry[:path]) if entry[:path] && File.exist?(entry[:path])
            registry.unregister(profile: entry[:profile], arch: entry[:arch])
          end
          puts "Removed #{entries.size} images"
        else
          puts "Use --orphaned to clean orphaned entries or --all to remove all images"
        end
      end
    end

    class Status < self
      desc "Show build system status"

      def call(**)
        config = Pim::BuildConfig.new
        resolver = Pim::ArchitectureResolver.new(config: config)

        puts "Build System Status"
        puts
        puts "Host architecture: #{resolver.host_arch}"
        puts "Image directory:   #{config.image_dir}"
        puts "Disk size:         #{config.disk_size}"
        puts "Memory:            #{config.memory} MB"
        puts "CPUs:              #{config.cpus}"
        puts
        puts "Builders:"

        %w[arm64 x86_64].each do |arch|
          builder = config.builder_for(arch)
          can_local = resolver.can_build_locally?(arch)
          status = case builder
                   when "local"
                     can_local ? "local (available)" : "local (unavailable - wrong arch)"
                   else
                     "remote: #{builder}"
                   end
          puts "  #{arch}: #{status}"
        end

        if config.remote_builders.any?
          puts
          puts "Remote builders:"
          config.remote_builders.each do |name, remote|
            puts "  #{name}: #{remote['host']}:#{remote['port'] || 22}"
          end
        end

        registry = Pim::Registry.new(image_dir: config.image_dir)
        images = registry.list
        puts
        puts "Cached images: #{images.size}"
      end
    end

    class Verify < self
      desc "Verify a built image by running its verification script"

      argument :build_id, required: true, desc: "Build recipe ID"

      option :verbose, type: :boolean, default: false, aliases: ["-v"], desc: "Show verification script output"

      def call(build_id:, verbose: false, **)
        config = Pim::Config.new

        build = Pim::Build.find(build_id)
        profile = build.resolved_profile

        puts "Verifying: #{build_id}"
        puts "  Profile: #{profile.id}"
        puts "  Arch:    #{build.arch}"
        puts

        verifier = Pim::Verifier.new(build: build, config: config)
        result = verifier.verify(verbose: verbose)

        puts
        if result.success
          puts "OK Verification passed (#{format_duration(result.duration)})"
        else
          puts "FAIL Verification failed (exit code: #{result.exit_code})"
          unless result.stderr.strip.empty?
            puts
            puts "Error output:"
            puts result.stderr
          end
          Pim.exit!(1)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Build '#{build_id}' not found")
      end

      private

      def format_duration(seconds)
        if seconds < 60
          "#{seconds.round(1)}s"
        else
          "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
        end
      end
    end
  end
end
```

#### `lib/pim/commands/targets_command.rb`

Consolidates: `commands/target.rb`, `commands/target/get.rb`

```ruby
# frozen_string_literal: true

module Pim
  class TargetsCommand < RestCli::Command
    class List < self
      desc "List all deploy targets"

      def call(**options)
        view.list(Pim::Target.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show target information"

      argument :id, required: true, desc: "Target ID"

      def call(id:, **options)
        target = Pim::Target.find(id)
        view.show(target, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Target '#{id}' not found")
      end
    end
  end
end
```

#### `lib/pim/commands/ventoy_command.rb`

Consolidates: `commands/ventoy.rb`, `commands/ventoy/prepare.rb`, `commands/ventoy/copy.rb`, `commands/ventoy/status.rb`, `commands/ventoy/config.rb`, `commands/ventoy/download.rb`

Ventoy has no FlatRecord model, so the outer class still inherits from `RestCli::Command` for consistency but none of the inner classes use the view layer.

```ruby
# frozen_string_literal: true

module Pim
  class VentoyCommand < RestCli::Command
    class Prepare < self
      desc "Install Ventoy to USB device"

      argument :device, required: false, desc: "Device path (e.g., /dev/sdX)"
      option :force, type: :boolean, default: false, aliases: ["-f"], desc: "Force installation without confirmation"

      def call(device: nil, force: false, **)
        manager = Pim::VentoyManager.new
        device ||= manager.config.device

        unless device
          puts "Error: No device specified and no default device in config"
          puts "Usage: pim ventoy prepare /dev/sdX"
          Pim.exit!(1)
        end

        device = manager.validate_device(device)
        Pim.exit!(1) unless device

        unless manager.verify_ventoy_install
          Pim.exit!(1)
        end

        unless manager.check_and_wipe_iso(device)
          Pim.exit!(1)
        end

        unless force
          print "WARNING: This will destroy all data on #{device}. Continue? (y/N) "
          response = $stdin.gets.chomp
          Pim.exit!(1) unless response.downcase == "y"
        end

        manager.install_ventoy(device)
      end
    end

    class Copy < self
      desc "Mount device and copy ISOs from pim-iso cache"

      argument :device, required: false, desc: "Device path (e.g., /dev/sdX1)"

      def call(device: nil, **)
        manager = Pim::VentoyManager.new
        device ||= manager.config.device

        if device && device !~ /\d+$/
          device = "#{device}1"
          puts "Using partition: #{device}"
        end

        unless device
          puts "Error: No device specified and no default device in config"
          puts "Usage: pim ventoy copy /dev/sdX1"
          Pim.exit!(1)
        end

        unless manager.mount_device(device)
          Pim.exit!(1)
        end

        begin
          manager.copy_isos
        ensure
          manager.unmount_device
        end
      end
    end

    class Status < self
      desc "Check Ventoy installation status"

      argument :device, required: false, desc: "Device path (e.g., /dev/sdX)"

      def call(device: nil, **)
        manager = Pim::VentoyManager.new
        device ||= manager.config.device

        unless device
          puts "Error: No device specified and no default device in config"
          puts "Usage: pim ventoy status /dev/sdX"
          Pim.exit!(1)
        end

        manager.status(device)
      end
    end

    class ShowConfig < self
      desc "Show ventoy configuration"

      def call(**)
        Pim::VentoyManager.new.show_config
      end
    end

    class Download < self
      desc "Download and verify Ventoy binaries"

      def call(**)
        config = Pim::Config.new
        manager = Pim::VentoyManager.new(config: config.ventoy)
        manager.ensure_ventoy!
      end
    end
  end
end
```

Note: `Config` inner class renamed to `ShowConfig` to avoid collision with the `Pim::Config` class.

#### `lib/pim/commands/config_command.rb`

Consolidates: `commands/config.rb`, `commands/config/list.rb`, `commands/config/get.rb`, `commands/config/set.rb`

Config commands don't use FlatRecord or the view layer — they read/write `pim.yml` directly. The outer class inherits from `RestCli::Command` for consistency.

```ruby
# frozen_string_literal: true

module Pim
  class ConfigCommand < RestCli::Command
    class List < self
      desc "List all configuration values"

      def call(**)
        config = Pim::Config.new
        flatten(config.runtime_config).each do |key, value|
          puts "#{key}=#{value}"
        end
      end

      private

      def flatten(hash, prefix = nil)
        result = []
        hash.each do |key, value|
          full_key = prefix ? "#{prefix}.#{key}" : key.to_s
          if value.is_a?(Hash)
            result.concat(flatten(value, full_key))
          else
            result << [full_key, value]
          end
        end
        result
      end
    end

    class Get < self
      desc "Get a configuration value by dot-notation key"

      argument :key, required: true, desc: "Configuration key (e.g., serve.port)"

      def call(key:, **)
        config = Pim::Config.new
        parts = key.split(".")
        value = config.runtime_config.dig(*parts)

        if value.nil?
          Pim.exit!(1, message: "Error: key '#{key}' not found")
        end

        if value.is_a?(Hash)
          flatten(value, key).each do |k, v|
            puts "#{k}=#{v}"
          end
        else
          puts value
        end
      end

      private

      def flatten(hash, prefix = nil)
        result = []
        hash.each do |key, value|
          full_key = prefix ? "#{prefix}.#{key}" : key.to_s
          if value.is_a?(Hash)
            result.concat(flatten(value, full_key))
          else
            result << [full_key, value]
          end
        end
        result
      end
    end

    class Set < self
      desc "Set a configuration value in the project pim.yml"

      argument :key, required: true, desc: "Configuration key (e.g., serve.port)"
      argument :value, required: true, desc: "Value to set"

      def call(key:, value:, **)
        project_root = Pim::Project.root!
        target = File.join(project_root, "pim.yml")

        data = if File.exist?(target)
                 YAML.load_file(target) || {}
               else
                 {}
               end

        parts = key.split(".")
        coerced = coerce(value)

        current = data
        parts[0..-2].each do |part|
          current[part] ||= {}
          current = current[part]
        end
        current[parts.last] = coerced

        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, YAML.dump(data))

        puts "#{key}=#{coerced}"
      end

      private

      def coerce(value)
        case value
        when /\A-?\d+\z/ then value.to_i
        when /\A-?\d+\.\d+\z/ then value.to_f
        when "true" then true
        when "false" then false
        else value
        end
      end
    end
  end
end
```

### CLI Registry rewrite

#### `lib/pim/cli.rb`

Complete rewrite to use new command class paths. Preserves all existing command names and aliases.

```ruby
# frozen_string_literal: true

require "dry/cli"

# Resource commands
require_relative "commands/profiles_command"
require_relative "commands/isos_command"
require_relative "commands/builds_command"
require_relative "commands/targets_command"
require_relative "commands/ventoy_command"
require_relative "commands/config_command"

# Standalone commands
require_relative "commands/version"
require_relative "commands/new"
require_relative "commands/console"
require_relative "commands/serve"

module Pim
  module CLI
    extend Dry::CLI::Registry

    # Standalone
    register "version",          Commands::Version
    register "new",              Commands::New
    register "console",          Commands::Console, aliases: ["c"]
    register "serve",            Commands::Serve, aliases: ["s"]

    # Profiles
    register "profile list",     ProfilesCommand::List
    register "profile ls",       ProfilesCommand::List
    register "profile show",     ProfilesCommand::Show
    register "profile get",      ProfilesCommand::Show          # backward compat alias
    register "profile add",      ProfilesCommand::Add

    # ISOs
    register "iso list",         IsosCommand::List
    register "iso ls",           IsosCommand::List
    register "iso show",         IsosCommand::Show
    register "iso get",          IsosCommand::Show              # backward compat alias
    register "iso download",     IsosCommand::Download
    register "iso verify",       IsosCommand::Verify
    register "iso add",          IsosCommand::Add

    # Builds
    register "build list",       BuildsCommand::List
    register "build ls",         BuildsCommand::List
    register "build show",       BuildsCommand::Show
    register "build get",        BuildsCommand::Show            # backward compat alias
    register "build run",        BuildsCommand::Run
    register "build clean",      BuildsCommand::Clean
    register "build status",     BuildsCommand::Status
    register "build verify",     BuildsCommand::Verify
    register "verify",           BuildsCommand::Verify, aliases: ["v"]  # top-level backward compat

    # Targets
    register "target list",      TargetsCommand::List
    register "target ls",        TargetsCommand::List
    register "target show",      TargetsCommand::Show
    register "target get",       TargetsCommand::Show           # backward compat alias

    # Ventoy
    register "ventoy prepare",   VentoyCommand::Prepare
    register "ventoy copy",      VentoyCommand::Copy
    register "ventoy status",    VentoyCommand::Status
    register "ventoy config",    VentoyCommand::ShowConfig
    register "ventoy download",  VentoyCommand::Download

    # Config
    register "config list",      ConfigCommand::List
    register "config ls",        ConfigCommand::List
    register "config get",       ConfigCommand::Get
    register "config set",       ConfigCommand::Set
  end
end
```

### Files to delete after consolidation

Remove the old directory-based command files:

```
lib/pim/commands/profile.rb
lib/pim/commands/profile/get.rb
lib/pim/commands/profile/add.rb
lib/pim/commands/iso.rb
lib/pim/commands/iso/get.rb
lib/pim/commands/iso/download.rb
lib/pim/commands/iso/verify.rb
lib/pim/commands/iso/add.rb
lib/pim/commands/build.rb
lib/pim/commands/build/get.rb
lib/pim/commands/build/run.rb
lib/pim/commands/build/clean.rb
lib/pim/commands/build/status.rb
lib/pim/commands/target.rb
lib/pim/commands/target/get.rb
lib/pim/commands/ventoy.rb
lib/pim/commands/ventoy/prepare.rb
lib/pim/commands/ventoy/copy.rb
lib/pim/commands/ventoy/status.rb
lib/pim/commands/ventoy/config.rb
lib/pim/commands/ventoy/download.rb
lib/pim/commands/config.rb
lib/pim/commands/config/list.rb
lib/pim/commands/config/get.rb
lib/pim/commands/config/set.rb
lib/pim/commands/verify.rb
```

Remove the now-empty directories:

```
lib/pim/commands/profile/
lib/pim/commands/iso/
lib/pim/commands/build/
lib/pim/commands/target/
lib/pim/commands/ventoy/
lib/pim/commands/config/
```

### Namespace note

The resource command classes are now at `Pim::ProfilesCommand`, not `Pim::Commands::Profile`. This is intentional — it matches the rest_cli convention and makes view lookup work (ProfilesCommand → ProfilesView). The standalone commands remain under `Pim::Commands::` since they don't participate in the view convention.

### View lookup compatibility

`RestCli::Command` derives the view class from the command class name: `ProfilesCommand::List` → `ProfilesView`. For this to work, both the command and view must be in the same module namespace. Since both are in `Pim::`, this works: `Pim::ProfilesCommand` → `Pim::ProfilesView`.

For `VentoyCommand` and `ConfigCommand`, there's no corresponding view, so any inner class that calls `view` will fail. This is fine because none of them call `view`. If needed later, a `VentoyView` or `ConfigView` can be added.

### Command name evolution

The old command names (`get`, `ls`) are preserved as aliases pointing to the new classes. New canonical names are added:

| Old | New canonical | Alias |
|-----|--------------|-------|
| `profile get` | `profile show` | `profile get` → Show |
| `profile ls` | `profile list` | `profile ls` → List |
| `iso get` | `iso show` | `iso get` → Show |
| `iso ls` | `iso list` | `iso ls` → List |
| `build get` | `build show` | `build get` → Show |
| `build ls` | `build list` | `build ls` → List |
| `target get` | `target show` | `target get` → Show |
| `target ls` | `target list` | `target ls` → List |

The old `get` commands combined list+show into one (no arg = list, with arg = show). The new structure separates them into `List` and `Show` classes. The `get` alias maps to `Show` for backward compatibility — users who typed `pim profile get` to see all profiles will now need `pim profile list`. This is a deliberate API improvement aligned with REST conventions.

## Test Spec

### Structural tests

```ruby
# spec/pim/commands/structure_spec.rb
RSpec.describe "command structure" do
  it "ProfilesCommand inherits from RestCli::Command" do
    expect(Pim::ProfilesCommand.superclass).to eq(RestCli::Command)
  end

  it "ProfilesCommand::List inherits from ProfilesCommand" do
    expect(Pim::ProfilesCommand::List.superclass).to eq(Pim::ProfilesCommand)
  end

  it "IsosCommand inherits from RestCli::Command" do
    expect(Pim::IsosCommand.superclass).to eq(RestCli::Command)
  end

  it "BuildsCommand inherits from RestCli::Command" do
    expect(Pim::BuildsCommand.superclass).to eq(RestCli::Command)
  end

  it "TargetsCommand inherits from RestCli::Command" do
    expect(Pim::TargetsCommand.superclass).to eq(RestCli::Command)
  end

  it "VentoyCommand inherits from RestCli::Command" do
    expect(Pim::VentoyCommand.superclass).to eq(RestCli::Command)
  end

  it "ConfigCommand inherits from RestCli::Command" do
    expect(Pim::ConfigCommand.superclass).to eq(RestCli::Command)
  end
end
```

### Registry completeness test

```ruby
# spec/pim/cli_spec.rb
RSpec.describe Pim::CLI do
  # Verify all expected commands are registered
  %w[
    profile\ list profile\ show profile\ add
    iso\ list iso\ show iso\ download iso\ verify iso\ add
    build\ list build\ show build\ run build\ clean build\ status build\ verify
    target\ list target\ show
    ventoy\ prepare ventoy\ copy ventoy\ status ventoy\ config ventoy\ download
    config\ list config\ get config\ set
    version new console serve verify
  ].each do |cmd|
    it "registers '#{cmd}'" do
      # Verify command is reachable through the registry
      # (Implementation depends on dry-cli internals — may need adjustment)
    end
  end
end
```

### No old files remain

```ruby
# spec/pim/commands/cleanup_spec.rb
RSpec.describe "old command files removed" do
  old_dirs = %w[
    lib/pim/commands/profile
    lib/pim/commands/iso
    lib/pim/commands/build
    lib/pim/commands/target
    lib/pim/commands/ventoy
    lib/pim/commands/config
  ]

  old_dirs.each do |dir|
    it "#{dir}/ directory does not exist" do
      expect(Dir.exist?(dir)).to be false
    end
  end

  old_files = %w[
    lib/pim/commands/profile.rb
    lib/pim/commands/iso.rb
    lib/pim/commands/build.rb
    lib/pim/commands/target.rb
    lib/pim/commands/ventoy.rb
    lib/pim/commands/config.rb
  ]

  old_files.each do |file|
    it "#{file} does not exist" do
      expect(File.exist?(file)).to be false
    end
  end
end
```

## Verification

```bash
# All specs pass
bundle exec rspec

# Manual smoke test — every command should work
pim version
pim profile list
pim profile show default
pim profile get default        # backward compat alias
pim profile list --format json
pim profile list --quiet
pim iso list
pim iso show <key>
pim iso ls                     # alias
pim build list
pim build show <id>
pim build status
pim build verify <id>          # canonical
pim verify <id>                # top-level backward compat alias
pim target list
pim target show <id>
pim config list
pim config get serve.port
pim config set serve.port 8080
pim ventoy config
pim ventoy download --help
pim console                    # Pry REPL loads

# No old files
ls lib/pim/commands/
# Should show: profiles_command.rb, isos_command.rb, builds_command.rb,
#              targets_command.rb, ventoy_command.rb, config_command.rb,
#              new.rb, console.rb, serve.rb, version.rb
```
