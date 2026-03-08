---
---

# Plan 01 — CLI Registration Cleanup

## Context

Read before starting:
- `lib/pim/cli.rb` — current CLI registry (the main file being changed)
- `lib/pim/commands/profiles_command.rb` — needs Remove stub
- `lib/pim/commands/isos_command.rb` — needs Remove stub
- `lib/pim/commands/targets_command.rb` — needs Add and Remove stubs
- `lib/pim/commands/ventoy_command.rb` — rename ShowConfig → Show
- `docs/cli-conventions/README.md` — tier overview with target state

Reference (do NOT modify):
- `~/.local/share/ppm/gems/pcs/lib/pcs/cli.rb` — PCS convention to match

## Implementation

### Step 1: Add missing command classes

**`lib/pim/commands/profiles_command.rb`** — Add `Remove` class:
```ruby
class Remove < self
  desc "Remove a profile"

  argument :id, required: true, desc: "Profile name"

  def call(id:, **)
    puts "Profile removal is not yet implemented."
    puts "Manually delete the profile YAML file from data/profiles/ in your project directory."
  end
end
```

**`lib/pim/commands/isos_command.rb`** — Add `Remove` class:
```ruby
class Remove < self
  desc "Remove an ISO from the catalog"

  argument :id, required: true, desc: "ISO key"

  def call(id:, **)
    puts "ISO removal is not yet implemented."
    puts "Manually delete the ISO YAML file from data/isos/ in your project directory."
  end
end
```

**`lib/pim/commands/targets_command.rb`** — Add `Add` and `Remove` classes:
```ruby
class Add < self
  desc "Add a new deploy target"

  def call(**)
    puts "Target creation is not yet implemented."
    puts "Manually add a YAML file to data/targets/ in your project directory."
  end
end

class Remove < self
  desc "Remove a deploy target"

  argument :id, required: true, desc: "Target ID"

  def call(id:, **)
    puts "Target removal is not yet implemented."
    puts "Manually delete the target YAML file from data/targets/ in your project directory."
  end
end
```

**`lib/pim/commands/ventoy_command.rb`** — Rename `ShowConfig` to `Show`:
- Rename the class from `ShowConfig` to `Show`
- Keep the same desc and implementation

### Step 2: Rewrite cli.rb registrations

Replace the entire `inside_project` block with:

```ruby
inside_project do
  register "console",          Commands::Console, aliases: ["c"]
  register "serve",            Commands::Serve, aliases: ["s"]

  # Profiles
  register "profile list",     ProfilesCommand::List, aliases: ["ls"]
  register "profile show",     ProfilesCommand::Show
  register "profile add",      ProfilesCommand::Add
  register "profile remove",   ProfilesCommand::Remove, aliases: ["rm"]

  # ISOs
  register "iso list",         IsosCommand::List, aliases: ["ls"]
  register "iso show",         IsosCommand::Show
  register "iso download",     IsosCommand::Download
  register "iso verify",       IsosCommand::Verify
  register "iso add",          IsosCommand::Add
  register "iso remove",       IsosCommand::Remove, aliases: ["rm"]

  # Builds
  register "build list",       BuildsCommand::List, aliases: ["ls"]
  register "build show",       BuildsCommand::Show
  register "build run",        BuildsCommand::Run
  register "build clean",      BuildsCommand::Clean
  register "build status",     BuildsCommand::Status
  register "build verify",     BuildsCommand::Verify
  register "verify",           BuildsCommand::Verify, aliases: ["v"]

  # Targets
  register "target list",      TargetsCommand::List, aliases: ["ls"]
  register "target show",      TargetsCommand::Show
  register "target add",       TargetsCommand::Add
  register "target remove",    TargetsCommand::Remove, aliases: ["rm"]

  # Ventoy
  register "ventoy prepare",   VentoyCommand::Prepare
  register "ventoy copy",      VentoyCommand::Copy
  register "ventoy status",    VentoyCommand::Status
  register "ventoy show",      VentoyCommand::Show
  register "ventoy download",  VentoyCommand::Download

  # Config
  register "config list",      ConfigCommand::List, aliases: ["ls"]
  register "config get",       ConfigCommand::Get
  register "config set",       ConfigCommand::Set
end
```

Key changes:
- All `ls` aliases use `aliases: ["ls"]` instead of separate registrations
- All `get` aliases for `show` are removed (profile, iso, build, target)
- `remove` added to profile, iso, target with `aliases: ["rm"]`
- `add` added to target
- Ventoy `config` → `show`
- Config keeps `get`/`set` (appropriate for key-value config)

### Step 3: Update specs

Check for any specs that reference the old command names (`get`, duplicate `ls` registrations) and update them. Key files to check:
- `spec/cli_spec.rb` or similar
- Any specs that test `pim profile get`, `pim iso get`, etc.

## Test Spec

After changes, verify:

```bash
# All existing specs pass
bundle exec rspec

# Manual verification of aliases
bundle exec ruby -e "require 'pim'; Pim.run 'profile --help'"
# Should show list, show, add, remove (no get, no duplicate ls)
```

## Verification

- [ ] `grep -c "register" lib/pim/cli.rb` shows no duplicate registrations for same command
- [ ] `grep "get" lib/pim/cli.rb` only matches `config get` (not profile/iso/build/target get)
- [ ] `grep "ShowConfig" lib/pim/commands/ventoy_command.rb` returns nothing (renamed to Show)
- [ ] `bundle exec rspec` passes
