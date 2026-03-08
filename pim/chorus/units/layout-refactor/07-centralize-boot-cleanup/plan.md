---
---

# Plan 07 — Centralize Boot and Final Cleanup

## Context

Read before starting:
- `lib/pim/boot.rb` — created in plan-05, `Pim.boot!`
- `lib/pim.rb` — main module, requires, Server class
- `lib/pim/models.rb` — `configure_flat_record!`
- All command files in `lib/pim/commands/` — check for ad-hoc `configure_flat_record!` calls
- `lib/pim/build/manager.rb` — calls `configure_flat_record!`
- `lib/pim/services/ventoy_manager.rb` — calls `configure_flat_record!`
- `CLAUDE.md` — project documentation

## Goal

Centralize all boot logic so `Pim.boot!` is the single entry point. Remove scattered `configure_flat_record!` calls. Final cleanup pass: remove dead code, update CLAUDE.md, ensure all specs green.

## Implementation

### 1. Centralize boot in CLI dispatch

The cleanest place to call `Pim.boot!` is early in CLI dispatch — after argument parsing identifies the command, but before execution. However, `pim new` and `pim version` must NOT boot (no project exists yet).

Two approaches:

**Option A: Boot in each command that needs it** — explicit but repetitive.

**Option B: Boot at CLI entry with skip list** — add a hook in `Pim.run`:

```ruby
# Commands that don't require a project
BOOT_SKIP_COMMANDS = %w[new version].freeze

def self.run(*args)
  flat_args = args.flat_map { |a| a.split(" ") }

  # Boot project unless running a skip command
  unless BOOT_SKIP_COMMANDS.include?(flat_args.first)
    boot!
  end

  Dry::CLI.new(Pim::CLI).call(arguments: flat_args)
rescue CommandError => e
  $stderr.puts e.message
rescue SystemExit
  # swallow exits in console mode
end
```

**Option C: Boot lazily on first `Pim.config` or `Pim.root!` access** — automatic but implicit.

Recommend **Option B** — it's explicit, centralized, and easy to reason about. The skip list is small and obvious.

### 2. Remove scattered `configure_flat_record!` calls

After boot is centralized, remove `configure_flat_record!` from:
- `lib/pim.rb` — `Config#profile` and `Config#profile_names` (Config class is gone after plan-06)
- `lib/pim/build/manager.rb` — line ~14
- `lib/pim/services/ventoy_manager.rb` — line ~276

These are now redundant since `boot!` calls `configure_flat_record!` once at startup.

### 3. Update `pim console` to use boot

```ruby
class Console < Dry::CLI::Command
  def call(**)
    require "pry"
    Pim.boot!
    Pim.console_mode!
    Pry.start(Pim)
  end
end
```

Since `console` is in the skip list... actually no, console DOES need boot. Only `new` and `version` skip. Update the skip list:

```ruby
BOOT_SKIP_COMMANDS = %w[new version].freeze
```

Console will boot via the centralized `Pim.run` path.

### 4. Clean up `lib/pim.rb`

After plans 05 and 06, `lib/pim.rb` should be significantly simpler:
- Remove the old `Pim::Config` class (replaced by DSL in plan-06)
- The `Server` class stays (it's still needed)
- Requires are updated for new file locations

### 5. Grep for dead references

```bash
grep -rn 'Pim::Project' lib/ spec/
grep -rn 'pim\.yml' lib/ spec/
grep -rn 'configure_flat_record' lib/
grep -rn 'runtime_config' lib/
grep -rn '\.env' lib/pim/new/
```

Fix any remaining references.

### 6. Update CLAUDE.md

Major sections to update:
- **Project-Oriented Design** — new layout with `pim.rb`, `data/`, `resources/`
- **Namespace** — remove `Pim::Project`, add `Pim::New::Scaffold`, update `Pim::Config` description
- **Code Organization** — update file tree to show `boot.rb`, `new/scaffold.rb`, `new/template/`, `config.rb`
- **Key Patterns** — replace "Unified Config" section with Ruby DSL pattern, add "Boot" pattern
- **Template/Script Naming Convention** — update directory references to `resources/`

### 7. Update README in `docs/layout-refactor/`

Mark all completion criteria as done.

## Test Spec

### Boot centralization test

```ruby
RSpec.describe "Pim.run boot" do
  it "boots project before command execution" do
    # Create temp project, verify Pim.config is populated after run
  end

  it "skips boot for pim new" do
    # Verify no error when running 'new' outside a project
  end

  it "skips boot for pim version" do
    # Verify no error when running 'version' outside a project
  end
end
```

### Verify no double-boot

Ensure `configure_flat_record!` is only called once during a normal command execution, not multiple times from scattered call sites.

### Full regression

```bash
bundle exec rspec
```

## Verification

```bash
# Full spec suite
bundle exec rspec

# No stale references
grep -rn 'Pim::Project' lib/ | wc -l        # 0
grep -rn 'pim\.yml' lib/ | wc -l            # 0 (except maybe comments)
grep -rn 'configure_flat_record' lib/ | wc -l  # 1 (only the definition in models.rb)

# Manual smoke test
pim version                      # works outside project
pim new /tmp/testfinal
cd /tmp/testfinal
pim profile list
pim iso list
pim build list
pim target list
pim config list
pim console                      # boots, Pim.config accessible
```
