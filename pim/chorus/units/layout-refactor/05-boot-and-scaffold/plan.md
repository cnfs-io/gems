---
---

# Plan 05 — Boot Module and Project Detection

## Context

Read before starting:
- `lib/pim/project.rb` — current Project class (detection + scaffolding mixed)
- `lib/pim.rb` — main module, Config class, Server class
- `lib/pim/models.rb` — `configure_flat_record!`
- `lib/pim/services/build_config.rb` — BuildConfig with DEFAULT_BUILD_CONFIG
- `lib/pim/services/ventoy_config.rb` — VentoyConfig
- `docs/layout-refactor/README.md` — tier context

## Goal

Extract project detection and boot logic from `Pim::Project` into module-level methods on `Pim`. Move scaffolding into `Pim::New::Scaffold`. Rename `builders/` to `resources/` throughout. This cleanly separates "find and boot a project" (used everywhere) from "create a new project" (used once by `pim new`).

## Implementation

### 1. Create `lib/pim/boot.rb`

Extract detection and boot into module-level methods:

```ruby
# frozen_string_literal: true

module Pim
  PROJECT_MARKER = "pim.rb"

  def self.root(start_dir = Dir.pwd)
    dir = File.expand_path(start_dir)
    loop do
      return dir if File.exist?(File.join(dir, PROJECT_MARKER))
      parent = File.dirname(dir)
      return nil if parent == dir
      dir = parent
    end
  end

  def self.root!(start_dir = Dir.pwd)
    root(start_dir) || raise("No pim.rb found. Run `pim new` to create a project.")
  end

  def self.project_dir
    @project_dir ||= root!
  end

  def self.data_dir(project_dir = nil)
    File.join((project_dir || self.project_dir), "data")
  end

  def self.resources_dir(project_dir = nil)
    File.join((project_dir || self.project_dir), "resources")
  end

  def self.boot!(project_dir: nil)
    @project_dir = project_dir || root!
    load File.join(@project_dir, PROJECT_MARKER)
    configure_flat_record!(project_dir: @project_dir)
  end

  def self.reset!
    @project_dir = nil
    @config = nil
  end
end
```

Notes:
- `PROJECT_MARKER` changes from `"pim.yml"` to `"pim.rb"`
- `boot!` calls `load` (not `require`) on `pim.rb` so it executes the configure block
- `reset!` is for testing — clears cached state between specs
- `project_dir` is memoized after first detection

### 2. Create `lib/pim/new/` directory and move scaffolding

Create `lib/pim/new/scaffold.rb`:

```ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module Pim
  module New
    class Scaffold
      SCAFFOLD_DIRS = %w[
        data/builds data/isos data/profiles data/targets
        resources/post_installs resources/preseeds resources/scripts resources/verifications
      ].freeze

      TEMPLATE_DIR = File.expand_path("template", __dir__)

      def initialize(target_dir)
        @target_dir = File.expand_path(target_dir)
      end

      def create
        if File.exist?(File.join(@target_dir, Pim::PROJECT_MARKER))
          raise "Project already exists at #{@target_dir}"
        end

        FileUtils.mkdir_p(@target_dir)

        SCAFFOLD_DIRS.each do |dir|
          FileUtils.mkdir_p(File.join(@target_dir, dir))
        end

        copy_templates

        puts "Created PIM project at #{@target_dir}"
        puts "  #{Pim::PROJECT_MARKER}"
        SCAFFOLD_DIRS.each { |d| puts "  #{d}/" }
      end

      private

      def copy_templates
        Dir.glob(File.join(TEMPLATE_DIR, "**", "*"), File::FNM_DOTMATCH).each do |src|
          next if File.directory?(src)

          rel = Pathname.new(src).relative_path_from(Pathname.new(TEMPLATE_DIR)).to_s
          dest = File.join(@target_dir, rel)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
        end
      end
    end
  end
end
```

### 3. Move templates directory and rename builders → resources

Move `lib/pim/templates/project/` → `lib/pim/new/template/`

Within the template directory, rename `builders/` to `resources/`:
- `lib/pim/new/template/resources/post_installs/default.sh`
- `lib/pim/new/template/resources/preseeds/default.cfg.erb`
- `lib/pim/new/template/resources/scripts/{base,finalize}.sh`
- `lib/pim/new/template/resources/verifications/default.sh`

The `TEMPLATE_DIR` in `Scaffold` uses `File.expand_path("template", __dir__)` which resolves to `lib/pim/new/template/`.

Delete `lib/pim/templates/` after moving (check if `starter/` is still needed — if so, move it somewhere appropriate or keep `templates/starter/` temporarily).

### 3b. Rename builders → resources in all source code

Search and replace across the codebase:
- `builders/` → `resources/` in all path strings
- `BUILDERS_DIR` → `RESOURCES_DIR`
- `Pim.builders_dir` → `Pim.resources_dir`
- `Pim::Project.builders_dir` → `Pim.resources_dir`

Known locations (from plans 01-04):
- `lib/pim/models/profile.rb` — `find_template('builders/preseeds', ...)` etc.
- `lib/pim/services/script_loader.rb` — `SCRIPTS_DIR = 'builders/scripts'`
- `lib/pim/services/verifier.rb` — error message referencing `builders/verifications/`
- `spec/` — any fixture paths using `builders/`

### 4. Update `lib/pim/commands/new.rb`

```ruby
def call(name: nil, **)
  target = name ? File.join(Dir.pwd, name) : Dir.pwd
  scaffold = Pim::New::Scaffold.new(target)
  scaffold.create
end
```

### 5. Delete `lib/pim/project.rb`

All functionality has been moved:
- Detection → `lib/pim/boot.rb` (`Pim.root`, `Pim.root!`, `Pim.project_dir`)
- Path helpers → `lib/pim/boot.rb` (`Pim.data_dir`, `Pim.builders_dir`)
- Scaffolding → `lib/pim/new/scaffold.rb` (`Pim::New::Scaffold`)

### 6. Update requires in `lib/pim.rb`

Replace:
```ruby
require_relative "pim/project"
```

With:
```ruby
require_relative "pim/boot"
require_relative "pim/new/scaffold"
```

### 7. Update all `Pim::Project` references across codebase

Search and replace:
- `Pim::Project.root!` → `Pim.root!`
- `Pim::Project.root` → `Pim.root`
- `Pim::Project.data_dir` → `Pim.data_dir`
- `Pim::Project.builders_dir` → `Pim.resources_dir`
- `Pim::Project.new(target).create` → `Pim::New::Scaffold.new(target).create`
- `Pim::Project::SCAFFOLD_DIRS` → `Pim::New::Scaffold::SCAFFOLD_DIRS`

Known callers:
- `lib/pim/models.rb` — `Pim::Project.root!`, `Pim::Project.data_dir`
- `lib/pim/models/profile.rb` — `Pim::Project.root!` in `find_template`
- `lib/pim.rb` — `Pim::Project.root!` in `Config.initialize`
- `lib/pim/services/script_loader.rb` — may reference project dir
- `lib/pim/commands/new.rb` — `Pim::Project.new`
- Various specs

For `Profile#find_template`, update to use `Pim.root!` instead of `Pim::Project.root!`.

### 8. Update `models.rb`

```ruby
def self.configure_flat_record!(project_dir: nil)
  project_dir ||= Pim.root!
  data_dir = Pim.data_dir(project_dir)
  # ... rest unchanged
end
```

## Test Spec

### Rename/rewrite `spec/pim/project_spec.rb` → split into two files:

**`spec/pim/boot_spec.rb`:**
- `Pim.root` — finds pim.rb in current dir
- `Pim.root` — finds pim.rb in parent dir
- `Pim.root` — returns nil when none found
- `Pim.root!` — returns root when found
- `Pim.root!` — raises with helpful message
- `Pim.data_dir` — returns data/ under project root
- `Pim.builders_dir` — returns builders/ under project root

Note: test fixtures must create `pim.rb` (not `pim.yml`) as the marker file. The `pim.rb` can be minimal: `Pim.configure { |c| }`

**`spec/pim/new/scaffold_spec.rb`:**
- All the `#create` tests from the old project_spec
- Updated to reference `Pim::New::Scaffold`
- Check for `pim.rb` as the marker (not `pim.yml`)

### Update all specs that reference `Pim::Project`

Grep for `Pim::Project` in spec/ and update.

## Verification

```bash
bundle exec rspec
# All pass

# No builders references remain
grep -rn 'builders' lib/ spec/ | wc -l   # 0

# Manual
pim new /tmp/testboot
ls /tmp/testboot/pim.rb           # exists (not pim.yml)
ls /tmp/testboot/resources/       # exists (not builders/)
cd /tmp/testboot && pim profile list  # works (boot! loads pim.rb)
```
