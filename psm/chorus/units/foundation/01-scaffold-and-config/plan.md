---
---

# Plan 01 — Project Scaffold and Config

## Goal

Establish PSM as a project-oriented gem with a working CLI entry point, XDG-compliant directory layout, and a unified config that deep-merges global (`~/.config/psm/`) over project-local (discovered from `$PWD` upward).

## Context

Read before implementing:

- `CLAUDE.md` — full architecture, namespace, config merge pattern
- `docs/foundation/README.md` — tier overview and completion criteria
- PIM's `lib/pim/project.rb` and `lib/pim.rb` — reference for XDG constants and project root detection pattern

## Deliverables

### 1. Gem entry point (`exe/psm`)

Thin binary that loads the gem and dispatches to `Psm::CLI`.

### 2. XDG Constants (`lib/psm.rb`)

```ruby
module Psm
  CONFIG_HOME = File.join(ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')), 'psm')
  DATA_HOME   = File.join(ENV.fetch('XDG_DATA_HOME',   File.expand_path('~/.local/share')), 'psm')
  CACHE_HOME  = File.join(ENV.fetch('XDG_CACHE_HOME',  File.expand_path('~/.cache')), 'psm')
  SYSTEM_DATA = '/opt/psm'
end
```

### 3. `Psm::Project` — project root detection

Walk up from `$PWD` looking for `psm.yml`. Return the directory containing it, or `nil` if none found (global-only mode). Mirror PIM's `Pim::Project.root` pattern.

### 4. `Psm::Config` — unified config

Reads `psm.yml` from global config dir and (if found) project root. Deep-merges project over global using ActiveSupport `Hash#deep_merge`. Exposes typed sub-configs as lazy accessors:

```ruby
config = Psm::Config.new
config.services   # → Psm::ServiceConfig
config.deploy     # → Psm::DeployConfig (default mode: user)
```

`psm.yml` schema (minimal for this plan):

```yaml
deploy:
  mode: user          # default deployment mode: user | system
```

### 5. `psm new <name>` command

Scaffolds a project directory:

```
<name>/
├── psm.yml
└── services.d/
    └── .keep
```

### 6. `psm config list|get|set` commands

Thin wrappers over `Psm::Config`. `list` shows merged config. `get <key>` returns a dot-path value. `set <key> <value>` writes to the project `psm.yml` (or global if no project).

### 7. `psm console` command

Pry REPL with `Psm` as context. `Psm.run "services list"` dispatches CLI commands from within the REPL.

## File layout after this plan

```
exe/
└── psm
lib/
├── psm.rb                   # Module, XDG constants, requires
└── psm/
    ├── version.rb
    ├── project.rb           # Project root detection
    ├── config.rb            # Psm::Config, Psm::DeployConfig
    ├── cli.rb               # tilos CLI registry
    └── commands/
        ├── new.rb
        ├── console.rb
        └── config/
            ├── list.rb
            ├── get.rb
            └── set.rb
spec/
├── spec_helper.rb
├── psm/
│   ├── project_spec.rb
│   └── config_spec.rb
└── fixtures/
    └── projects/
        ├── global/          # Simulated ~/.config/psm/
        │   └── psm.yml
        └── with_project/    # Project with psm.yml override
            ├── psm.yml
            └── services.d/
```

## Tests

- `Psm::Project.root` returns correct dir when `psm.yml` exists in ancestors
- `Psm::Project.root` returns `nil` when no `psm.yml` found
- `Psm::Config` loads global config when no project present
- `Psm::Config` deep-merges project config over global (project wins)
- `psm new` creates expected directory structure
- `psm config get deploy.mode` returns correct value from merged config

## Dependencies introduced

- `tilos` — CLI framework
- `activesupport` — `Hash#deep_merge`
- `pry` — console
