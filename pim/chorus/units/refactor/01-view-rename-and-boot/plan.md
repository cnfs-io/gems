---
---

# Plan 01 — View Rename and Boot Centralization

## Objective

Two small but foundational changes: (1) update the ProfilesView to use `RestCli::View` instead of `RestCli::Base` (matching rest_cli's reorganization), and (2) centralize `Pim.configure_flat_record!` so it's called once at boot rather than in every command.

## Context

Read before starting:
- `lib/pim/views/profiles_view.rb` — current view (references `RestCli::Base`)
- `lib/pim/views.rb` — view require file
- `lib/pim.rb` — main module, contains `configure_flat_record!`
- `lib/pim/cli.rb` — CLI registry
- `lib/pim/commands/profile/get.rb` — example command that calls `Pim.configure_flat_record!`
- `lib/pim/commands/iso/get.rb` — another command that calls it
- `lib/pim/commands/build/get.rb` — another
- `lib/pim/commands/build/run.rb` — another
- `lib/pim/commands/build/clean.rb` — another
- `lib/pim/commands/build/status.rb` — another
- `lib/pim/commands/target/get.rb` — another
- `bin/pim` or `exe/pim` — the executable entry point

## Implementation Spec

### 1. Update ProfilesView

Change `RestCli::Base` to `RestCli::View`:

```ruby
# lib/pim/views/profiles_view.rb
# frozen_string_literal: true

module Pim
  class ProfilesView < RestCli::View
    columns       :id, :hostname, :username
    detail_fields :id, :hostname, :username, :fullname, :timezone, :domain,
                  :locale, :keyboard, :packages
  end
end
```

### 2. Centralize flat_record boot

Find the PIM executable entry point (likely `bin/pim` or `exe/pim`) and ensure `Pim.configure_flat_record!` is called before CLI dispatch. This is analogous to `Application.boot!` in a rest_cli app.

If the executable currently looks like:

```ruby
#!/usr/bin/env ruby
require_relative "../lib/pim"
Dry::CLI.new(Pim::CLI).call
```

Change to:

```ruby
#!/usr/bin/env ruby
require_relative "../lib/pim"
Pim.configure_flat_record!
Dry::CLI.new(Pim::CLI).call
```

**Note:** `configure_flat_record!` requires a project context (it reads `pim.yml`). Some commands like `pim new` and `pim version` don't need a project. The current code handles this by calling `configure_flat_record!` only in commands that need it. We need to make the boot conditional:

```ruby
#!/usr/bin/env ruby
require_relative "../lib/pim"
Pim.configure_flat_record! if Pim::Project.root
Dry::CLI.new(Pim::CLI).call
```

Or, if `configure_flat_record!` already handles the no-project case gracefully (returns early if no project root found), just call it unconditionally.

Check the implementation of `Pim.configure_flat_record!` and `Pim::Project.root` to determine the right approach.

### 3. Remove `Pim.configure_flat_record!` from individual commands

Search all command files for `Pim.configure_flat_record!` and remove those calls. After this change, flat_record is always configured before any command runs.

Files to check (at minimum):
- `lib/pim/commands/profile/get.rb`
- `lib/pim/commands/iso/get.rb`
- `lib/pim/commands/build/get.rb`
- `lib/pim/commands/build/run.rb`
- `lib/pim/commands/build/clean.rb`
- `lib/pim/commands/build/status.rb`
- `lib/pim/commands/target/get.rb`
- `lib/pim/commands/config/get.rb`
- `lib/pim/commands/config/set.rb`

Use `grep -r "configure_flat_record" lib/pim/commands/` to find all occurrences.

### Design notes

- This plan makes no structural changes to commands — just updates the view reference and moves boot to the entry point. Plans 02 and 03 do the heavy restructuring.
- The boot centralization is safe because `configure_flat_record!` is idempotent — calling it when there's no project root should be a no-op, not an error. Verify this.
- The `pim console` command also calls `configure_flat_record!` in its own way (for the Pry REPL). Check whether it needs special handling or if the centralized boot covers it.

## Test Spec

### Verify ProfilesView works with new class name

```ruby
# In existing profile view specs or manual test
RSpec.describe Pim::ProfilesView do
  it "inherits from RestCli::View" do
    expect(described_class.superclass).to eq(RestCli::View)
  end

  it "has columns defined" do
    expect(described_class.columns).to eq([:id, :hostname, :username])
  end
end
```

### Verify boot centralization

```ruby
# Verify configure_flat_record! is not called in any command file
RSpec.describe "boot centralization" do
  it "no command files call configure_flat_record! directly" do
    command_files = Dir.glob(File.join(__dir__, "../../lib/pim/commands/**/*.rb"))
    command_files.each do |file|
      content = File.read(file)
      expect(content).not_to include("configure_flat_record!"),
        "#{file} still calls configure_flat_record! — remove it"
    end
  end
end
```

## Verification

```bash
# ProfilesView loads correctly
bundle exec ruby -e "require 'pim'; puts Pim::ProfilesView.superclass"
# Should output: RestCli::View

# No commands call configure_flat_record!
grep -r "configure_flat_record" lib/pim/commands/
# Should return empty

# All existing specs pass
bundle exec rspec

# Manual smoke test
pim profile get
pim profile get default
pim iso get
pim build get
pim target get
pim version
pim new --help
```
