---
---

# Plan 02 — Fixture Strategy (Scaffold as Single Source of Truth)

## Context

Read before starting:
- `spec/spec_helper.rb`
- `spec/pim/new/scaffold_spec.rb`
- `spec/pim/boot_spec.rb`
- `spec/pim/models/profile_spec.rb`
- `spec/pim/models/build_spec.rb`
- `spec/pim/models/iso_spec.rb`
- `spec/pim/models/target_spec.rb`
- `lib/pim/new/scaffold.rb`
- `lib/pim/new/template/` (entire directory tree)
- `docs/collection-layout/plan-01-collection-layout-and-defaults.md` (must be complete first)

## Depends On

Plan 01 (collection-layout-and-defaults) must be complete. This plan assumes collection layout YAML files exist in the template directory.

## Problem

Every model spec creates its own fixture data inline using `write_yaml` or `write_profiles` helpers that manually write YAML to tmpdir subdirectories. This has several issues:

1. **Duplication** — fixture data is duplicated across specs and diverges from the template defaults
2. **Individual layout hardcoded** — helpers like `write_profiles` create individual-layout subdirectories (`profiles/default.yml`), which will break after plan-01 switches to collection layout
3. **No single source of truth** — template data and test data are maintained separately

## Solution

Use `Pim::New::Scaffold` to create test projects. The scaffold copies the real template files, so specs automatically use the same data that `pim new` produces.

### Shared Test Project Helper

Create `spec/support/test_project.rb`:

```ruby
# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module TestProject
  # Creates a scaffold project in a tmpdir, boots PIM against it.
  # Returns the project directory path.
  #
  # Usage:
  #   let(:project_dir) { TestProject.create }
  #   after { TestProject.cleanup(project_dir) }
  #
  # Or for specs that need to mutate data, use a fresh copy each time.
  def self.create(name: "test-project")
    tmp = Dir.mktmpdir("pim-spec-")
    target = File.join(tmp, name)
    Pim::New::Scaffold.new(target).create
    target
  end

  # Boot PIM against a project directory.
  # Call this after create, or after modifying data files.
  def self.boot(project_dir)
    Pim.boot!(project_dir: project_dir)
  end

  # Create and boot in one call.
  def self.create_and_boot(name: "test-project")
    dir = create(name: name)
    boot(dir)
    dir
  end

  # Cleanup a project tmpdir.
  def self.cleanup(project_dir)
    Pim.reset!
    # The tmpdir parent is one level up from the project dir
    parent = File.dirname(project_dir)
    FileUtils.remove_entry(parent) if parent.start_with?(Dir.tmpdir)
  end

  # Write additional records into a project's collection YAML file.
  # Merges with existing records (by appending).
  #
  #   TestProject.append_records(project_dir, "profiles", [
  #     { "id" => "dev", "parent_id" => "default", "packages" => "vim git" }
  #   ])
  #
  def self.append_records(project_dir, source_name, records)
    backend = FlatRecord.backend_for(:yaml)
    path = File.join(project_dir, "data", "#{source_name}#{backend.extension}")

    existing = if File.exist?(path)
                 YAML.safe_load(File.read(path)) || []
               else
                 []
               end

    File.write(path, YAML.dump(existing + records))
  end

  # Overwrite a collection YAML file entirely.
  def self.write_records(project_dir, source_name, records)
    backend = FlatRecord.backend_for(:yaml)
    path = File.join(project_dir, "data", "#{source_name}#{backend.extension}")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(records))
  end
end
```

### Require the helper

In `spec/spec_helper.rb`, add:

```ruby
require_relative "support/test_project"
```

### Migration Strategy for Existing Specs

The goal is NOT to rewrite every spec in one shot. Instead:

1. **Specs that only read default data** — switch to `TestProject.create_and_boot`, remove inline fixture helpers
2. **Specs that need custom data beyond defaults** — use `TestProject.create`, then `TestProject.append_records` to add extra records, then `TestProject.boot`
3. **Specs that test mutation (create/update/destroy)** — use `TestProject.create` per example (fresh copy each time) so mutations don't leak
4. **Specs that test empty state** — keep using bare tmpdir with direct FlatRecord config (no scaffold needed)

### Specific Spec Updates

#### `spec/pim/models/profile_spec.rb`

The profile spec has the most complex fixtures (parent chains, multi-path merging). Approach:

- **`.all` and `.find` basic tests**: Use scaffold defaults (already has `default` profile)
- **Parent chain tests**: Use `TestProject.create`, then `append_records` to add `dev` and `dev-roberto` profiles, then boot
- **Multi-path/deep merge tests**: Keep the existing two-tmpdir approach since this tests FlatRecord multi-path, not scaffold
- **Template resolution tests**: Use scaffold project (has real resource files)
- **Read-only test**: This test should be REMOVED after plan-01 removes read_only. Models are now writable.

#### `spec/pim/models/build_spec.rb`

- **Basic tests**: Use scaffold defaults (already has `default` build with `default` profile, `debian-13-amd64` ISO, `local` target)
- **Override tests** (`dev-fedora` with custom disk/memory/cpus): Use `TestProject.append_records`
- **Read-only test**: REMOVE (models are now writable)
- Remove `write_yaml` helper — replaced by `TestProject.write_records` / `TestProject.append_records`

#### `spec/pim/models/iso_spec.rb`

- **Basic tests**: Use scaffold defaults (has two ISOs)
- **Download/verify tests**: These mock `Pim::HTTP` and `Digest` — keep mocks but use scaffold ISO records
- **Read-only test**: REMOVE

#### `spec/pim/models/target_spec.rb`

- **Basic tests and STI**: Use scaffold `local` target, append proxmox/aws targets for STI tests
- **Parent chain tests**: Append proxmox parent/child targets
- **Read-only test**: REMOVE

#### `spec/pim/new/scaffold_spec.rb`

- Update to verify new collection layout structure:
  - `data/profiles.yml` exists (not `data/profiles/default.yml`)
  - `data/isos.yml` exists with 2 records
  - `data/builds.yml` exists with 1 record
  - `data/targets.yml` exists with 1 record
  - No `data/profiles/`, `data/builds/`, `data/isos/`, `data/targets/` subdirectories

#### `spec/pim/boot_spec.rb`

- The "full boot cycle from scaffold" test already uses `Scaffold.new`. It should work as-is after plan-01 changes.

### What NOT to Change

- `spec/pim/views/*_spec.rb` — these don't use fixtures, just test class metadata
- `spec/pim/cli_spec.rb` — tests CLI routing, no fixtures needed
- `spec/pim/config_spec.rb` — tests config DSL, no fixtures needed
- `spec/pim/namespace_spec.rb` — tests module structure, no fixtures needed

## Test Spec

1. **test: TestProject.create scaffolds a valid project** — `TestProject.create` returns a directory containing `pim.rb`, `data/profiles.yml`, etc.

2. **test: TestProject.create_and_boot loads models** — After `create_and_boot`, `Pim::Profile.all` returns profiles, `Pim::Build.all` returns builds, etc.

3. **test: TestProject.append_records adds records** — After appending a profile, `Pim::Profile.all` includes both the default and the new one.

4. **test: TestProject.write_records replaces data** — After writing, only the written records exist.

5. **test: existing model specs still pass** — Run full suite, all green.

6. **test: no read-only specs exist** — Grep for `ReadOnlyError` in spec files — should find zero matches.

## Verification

```bash
bundle exec rspec
```

All green. Also verify:

```bash
grep -r "ReadOnlyError" spec/    # should return nothing
grep -r "write_yaml\|write_profiles\|write_isos" spec/  # should only be in TestProject helper or gone
```
