---
---

# Plan 02: Project Structure

## Context

Read these files before starting:

- `lib/pim.rb` — `Pim::Config`, `Pim::Profile`, `Pim::CLI` (after plan-01 changes)
- `lib/pim/config.rb` — `PimConfig::CLI` with existing `config set --project` flag
- `lib/pim/profile.rb` — `PimProfile::Config` with `project_dir:` parameter
- `lib/pim/build.rb` — `PimBuild::Config`, `PimBuild::ScriptLoader` — both already check `$PWD`
- `lib/pim/iso.rb` — `PimIso::Config` — check how it resolves ISO catalog files
- `~/.config/pim/` — current global config structure (reference for what to scaffold)

## Objective

Make PIM project-oriented. `pim new` scaffolds a self-contained project directory. All commands resolve config, profiles, templates, and scripts from the project directory. The global `~/.config/pim/` fallback is removed — projects are self-contained.

## Design decisions

### Project directory layout

```
myproject/
├── pim.yml                  # Project config (build settings, serve defaults)
├── profiles.d/
│   └── default.yml          # At least a default profile
├── isos.d/
│   └── default.yml          # ISO catalog (which ISOs to use)
├── preseeds.d/
│   └── default.cfg.erb      # Preseed template
├── installs.d/
│   └── default.sh           # Late-command install script
├── scripts.d/
│   ├── base.sh              # Provisioning scripts (run in order)
│   └── finalize.sh
└── verifications.d/
    └── default.sh           # Verification script (plan-03)
```

### No global fallback

After this plan, PIM requires a project directory. Running `pim build run` outside a project fails with a clear error: "No pim.yml found. Run `pim new` to create a project."

Detection: check for `pim.yml` in `Dir.pwd`. This is the project marker file.

### `pim new` behavior

`pim new [NAME]` creates the project directory with scaffold files:

- If `NAME` is given: creates `./NAME/` and scaffolds inside it
- If no `NAME`: scaffolds in `$PWD` (current directory must be empty or have no `pim.yml`)

The scaffold includes working defaults — a default profile with sensible values, a default preseed template for Debian, a default ISO entry, and stub scripts. The goal is that `pim new myproject && cd myproject && pim build run default` works immediately (given an ISO is cached or downloadable).

### Config resolution changes

`Pim::Config` changes:

- `project_dir:` parameter becomes required (defaults to `Dir.pwd` still, but must contain `pim.yml`)
- Remove global config loading from `~/.config/pim/pim.yml`
- Add `Pim::Config.project_root` class method that walks up from `Dir.pwd` looking for `pim.yml` (like how git finds `.git/`)
- All `.d/` directory resolution uses project dir only

`PimProfile::Config` changes:

- Remove `GLOBAL_CONFIG_D` constant and global profiles loading
- Load only from `project_dir/profiles.d/`

`PimIso::Config` changes:

- Remove global ISO directory loading
- Load only from `project_dir/isos.d/`

`PimBuild::ScriptLoader` changes:

- Remove global `scripts.d/` fallback
- Load only from `project_dir/scripts.d/`

`Pim::Profile` (the model) changes:

- Remove global template fallback in `find_template`
- Look only in `project_dir/`

### XDG data and cache remain global

These are NOT part of the project — they are machine-local:

- `~/.local/share/pim/images/` — built images
- `~/.local/share/pim/registry.yml` — image registry
- `~/.cache/pim/isos/` — downloaded ISOs

These stay as-is and are not affected by the project structure change.

## Implementation

### 1. Scaffold generator

Create `lib/pim/project.rb`:

```ruby
module Pim
  class Project
    SCAFFOLD_DIRS = %w[profiles.d isos.d preseeds.d installs.d scripts.d verifications.d].freeze
    PROJECT_MARKER = "pim.yml"

    def self.root(start_dir = Dir.pwd)
      dir = File.expand_path(start_dir)
      loop do
        return dir if File.exist?(File.join(dir, PROJECT_MARKER))
        parent = File.dirname(dir)
        return nil if parent == dir  # reached filesystem root
        dir = parent
      end
    end

    def self.root!(start_dir = Dir.pwd)
      root(start_dir) || raise("No pim.yml found. Run `pim new` to create a project.")
    end

    def initialize(target_dir)
      @target_dir = File.expand_path(target_dir)
    end

    def create
      # implementation: mkdir_p each scaffold dir, write default files
    end
  end
end
```

### 2. Default scaffold files

The scaffold files should be embedded in the gem (not copied from `~/.config/pim/`). Store them as templates:

Create `lib/pim/templates/` directory containing:

- `pim.yml` — default project config
- `profiles.d/default.yml` — default profile (hostname, username, password, timezone, locale, packages including qemu-guest-agent)
- `isos.d/default.yml` — default ISO entry (latest Debian stable)
- `preseeds.d/default.cfg.erb` — working Debian preseed
- `installs.d/default.sh` — default late-command script
- `scripts.d/base.sh` — base provisioning (apt update, install essentials)
- `scripts.d/finalize.sh` — cleanup script (cloud-init clean, truncate logs)
- `verifications.d/default.sh` — marker file check (stub for plan-03)

Copy the content for these from the existing files in `~/.config/pim/`. The preseed template in particular should be the working one that was used for the successful build last week.

### 3. `pim new` CLI command

Add to `Pim::CLI`:

```ruby
desc 'new [NAME]', 'Create a new PIM project'
def new(name = nil)
  target = name ? File.join(Dir.pwd, name) : Dir.pwd
  project = Pim::Project.new(target)
  project.create
end
```

### 4. Update Config to require project context

Modify `Pim::Config#initialize`:

- Use `Pim::Project.root!` to find project root
- Load `pim.yml` from project root only
- Pass project root to all sub-configs

### 5. Update all config loaders

Each loader that currently checks global dirs needs to be updated to use project dir only. This is straightforward since they all already accept `project_dir:` — just remove the global fallback paths.

### 6. Guard on CLI commands

Commands that require a project context (everything except `pim new`) should fail early with a helpful message if no project is found.

## Test spec

### `spec/pim/project_spec.rb`

Test `Pim::Project.root`:

- Finds `pim.yml` in current directory
- Finds `pim.yml` in parent directory (subdirectory of project)
- Returns `nil` when no `pim.yml` exists up the tree

Test `Pim::Project.root!`:

- Raises with helpful message when no project found

Test `Pim::Project#create`:

- Creates target directory if it doesn't exist
- Creates all scaffold subdirectories
- Writes `pim.yml` with valid YAML content
- Writes default profile in `profiles.d/default.yml`
- Writes preseed template in `preseeds.d/default.cfg.erb`
- Writes ISO config in `isos.d/default.yml`
- Writes install script in `installs.d/default.sh`
- Writes provisioning scripts in `scripts.d/`
- Writes verification stub in `verifications.d/default.sh`
- Does not overwrite existing `pim.yml` (error if project already exists)
- All scaffold files are valid (YAML parses, ERB renders, shell scripts have shebang)

### `spec/pim/config_spec.rb` (update from plan-01)

Add/modify tests:

- Loads config from project directory only (no global fallback)
- Raises when no project directory found
- Works when invoked from a subdirectory of the project

### `spec/pim/profile_spec.rb` (update from plan-01)

Add/modify tests:

- Loads profiles from project `profiles.d/` only
- Template resolution checks project directory only
- No global fallback behavior

## Verification

```bash
# Unit specs pass
bundle exec rspec spec/pim/project_spec.rb
bundle exec rspec

# Scaffold works
cd /tmp
pim new testproject
ls testproject/           # shows pim.yml, profiles.d/, etc.
cat testproject/pim.yml   # valid YAML
cd testproject
pim profile list          # shows 'default'
pim config list           # shows config from pim.yml

# No global config references remain
grep -r "\.config/pim" lib/   # should return nothing (except maybe in comments)
grep -r "GLOBAL_CONFIG" lib/  # should return nothing

# Clean up
rm -rf /tmp/testproject
```
