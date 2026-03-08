---
---

# Plan 01 — Scaffold and Templates

## Context

Read before starting:
- `lib/pim/project.rb` — Project class with SCAFFOLD_DIRS and template copying
- `lib/pim/templates/project/` — current template directory structure
- `docs/layout-refactor/README.md` — target layout

## Goal

Restructure the template directory to match the new layout and update the Project class to scaffold it correctly.

## Implementation

### 1. Restructure `lib/pim/templates/project/`

Move from:
```
templates/project/
├── builds.yml
├── isos.yml
├── pim.yml
├── profiles.yml
├── targets.yml
├── installs.d/default.sh
├── preseeds.d/default.cfg.erb
├── scripts.d/{base,finalize}.sh
└── verifications.d/default.sh
```

To:
```
templates/project/
├── .env
├── pim.yml
├── data/
│   ├── builds/default.yml
│   ├── isos/default.yml
│   ├── profiles/default.yml
│   └── targets/default.yml
├── builders/
│   ├── post_installs/default.sh
│   ├── preseeds/default.cfg.erb
│   ├── scripts/{base,finalize}.sh
│   └── verifications/default.sh
```

### 2. Content changes

- **`.env`** — create new file with placeholder comments:
  ```
  # PIM Environment Configuration
  # Uncomment and set values to override pim.yml settings
  # PIM_ISO_DIR=
  # PIM_IMAGE_DIR=
  ```

- **`data/builds/default.yml`** — move content from `builds.yml`, keep exact same YAML content
- **`data/isos/default.yml`** — move content from `isos.yml`
- **`data/profiles/default.yml`** — move content from `profiles.yml`
- **`data/targets/default.yml`** — move content from `targets.yml`
- **`builders/post_installs/default.sh`** — move content from `installs.d/default.sh`
- **`builders/preseeds/default.cfg.erb`** — move content from `preseeds.d/default.cfg.erb`
- **`builders/scripts/{base,finalize}.sh`** — move content from `scripts.d/{base,finalize}.sh`
- **`builders/verifications/default.sh`** — move content from `verifications.d/default.sh`

### 3. Update `lib/pim/project.rb`

- Update `SCAFFOLD_DIRS` constant:
  ```ruby
  SCAFFOLD_DIRS = %w[
    data/builds data/isos data/profiles data/targets
    builders/post_installs builders/preseeds builders/scripts builders/verifications
  ].freeze
  ```

- The `copy_templates` method should work unchanged — it globs all files recursively and preserves relative paths. Verify it handles nested directories (it uses `File.dirname(dest)` with `mkdir_p` so it should).

- Update the `create` output to show the new structure cleanly.

### 4. Delete old template files

Remove:
- `templates/project/builds.yml`
- `templates/project/isos.yml`
- `templates/project/profiles.yml`
- `templates/project/targets.yml`
- `templates/project/installs.d/` (entire directory)
- `templates/project/preseeds.d/` (entire directory)
- `templates/project/scripts.d/` (entire directory)
- `templates/project/verifications.d/` (entire directory)

## Test Spec

Update `spec/pim/project_spec.rb`:

- `SCAFFOLD_DIRS` test should check for new directory names
- "writes profiles.yml" → check `data/profiles/default.yml` exists and contains default profile
- "writes preseed template" → check `builders/preseeds/default.cfg.erb`
- "writes isos.yml" → check `data/isos/default.yml`
- "writes builds.yml" → check `data/builds/default.yml`
- "writes targets.yml" → check `data/targets/default.yml`
- "writes install script" → check `builders/post_installs/default.sh`
- "writes provisioning scripts" → check `builders/scripts/{base,finalize}.sh`
- "writes verification stub" → check `builders/verifications/default.sh`
- Add: "writes .env file" → check `.env` exists
- The "scaffold files produce valid config" test will fail at this point — that's expected, it'll be fixed in plan-02

**Note:** The config integration test at the bottom of project_spec.rb (`scaffold files produce valid config`) will break because FlatRecord data_paths haven't been updated yet. Mark this test as `pending "layout-refactor plan-02"` for now.

## Verification

```bash
bundle exec rspec spec/pim/project_spec.rb
# All pass except the config integration test (pending)

# Manual: create a test project and verify layout
cd /tmp && pim new testproject && find testproject -type f | sort
```
