---
objective: "Switch PIM's data directory from individual file layout to collection layout. Seed new projects with buildable defaults."
status: complete
---

# Collection Layout Tier — PIM

## Objective

Switch PIM's data directory from individual file layout (one YAML file per record in subdirectories) to collection layout (one YAML file per model containing an array of records). Remove dead `read_only` references. Seed new projects with buildable defaults (ISOs, a build, a target).

**The question this tier answers:** Can a new `pim new` project build an image with zero manual data entry?

## Background

After the simplification tier, PIM's project data directory uses FlatRecord's individual layout:

```
data/
  builds/          # empty dir
  isos/            # empty dir
  profiles/
    default.yml    # single record
  targets/
    local.yml      # single record
```

This is more structure than needed. FlatRecord's collection layout is simpler — one file per model:

```
data/
  builds.yml       # YAML array of build records
  isos.yml         # YAML array of ISO records
  profiles.yml     # YAML array of profile records
  targets.yml      # YAML array of target records
```

Additionally, `read_only true` was commented out in all four models during the layout-refactor tier but the lines were left behind. They should be removed.

Finally, `pim new` currently creates a project with no ISOs and no builds, meaning the user must manually add both before they can build anything. The scaffold should include Debian 13.3 ISOs (amd64 + arm64) and a default build so the project is buildable out of the box (after downloading the ISO).

## Design Decisions

### Collection layout is the default

FlatRecord's `file_layout` defaults to `:collection`. Removing the `file_layout :individual` declarations from all four models is sufficient. No FlatRecord changes needed.

### Scaffold creates flat files, not directories

`SCAFFOLD_DIRS` no longer includes `data/*` subdirectories. Template files become `data/profiles.yml`, `data/targets.yml`, `data/isos.yml`, `data/builds.yml` — each containing a YAML array.

### Two ISOs seeded: Debian 13.3 amd64 and arm64

Both use `checksum_url` pointing at the official SHA256SUMS file. PIM's ISO verification code downloads and parses this at runtime. No hardcoded checksums.

### Default build references default profile + debian-13-amd64 ISO + local target

This means `pim iso download debian-13-amd64 && pim build run default` works immediately after `pim new`.

## Plans

| # | Name | Depends On | Description |
|---|------|------------|-------------|
| 01 | collection-layout-and-defaults | — | Switch models to collection layout, update scaffold, seed defaults, remove read_only |
| 02 | fixture-strategy | 01 | Replace duplicated spec fixtures with scaffold-generated test projects |
| 03 | e2e-build-verify | 02 | End-to-end test: download ISO, build image, verify |

## Completion Criteria

- All four models use collection layout (no `file_layout` declaration)
- No `read_only` references in any model file
- `SCAFFOLD_DIRS` has no `data/*` entries
- Template directory has `data/{builds,isos,profiles,targets}.yml` (no subdirectories under data/)
- `pim new foo && cd foo && pim iso list` shows two ISOs
- `pim new foo && cd foo && pim build list` shows one build
- `spec/support/test_project.rb` exists and is used by model specs
- No duplicated fixture YAML in spec files (single source of truth is the template)
- No `ReadOnlyError` references in any spec file
- `bundle exec rspec` passes (all unit + integration specs)
- `bundle exec rspec --tag e2e` runs the full build+verify pipeline
- E2E spec detects host arch and uses the correct ISO
- E2E spec skips gracefully when QEMU/bsdtar not installed

