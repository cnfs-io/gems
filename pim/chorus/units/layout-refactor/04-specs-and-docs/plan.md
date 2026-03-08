---
---

# Plan 04 — Specs and Docs

## Context

Read before starting:
- `spec/` — all spec files, check for any remaining old path references
- `CLAUDE.md` — project documentation at gem root
- `docs/layout-refactor/README.md` — completion criteria checklist

## Goal

Final pass: ensure all specs pass, sweep for any remaining old path references, update CLAUDE.md documentation to reflect the new layout.

## Implementation

### 1. Grep for old path references

Search entire codebase for lingering references to old directory names:

```bash
grep -rn 'preseeds\.d\|installs\.d\|scripts\.d\|verifications\.d\|profiles\.d\|isos\.d' lib/ spec/
grep -rn "builds\.yml\|isos\.yml\|profiles\.yml\|targets\.yml" lib/ spec/ --include='*.rb'
```

Fix any remaining references. Likely places:
- Spec fixture setup
- Error messages or help text in CLI commands
- Comments in source files

### 2. Update CLAUDE.md

Replace the "Project-Oriented Design" section with the new layout:

```markdown
## Project-Oriented Design

PIM is project-oriented. All configuration lives in a project directory created by `pim new`:

\```
myproject/
├── .env                     # Environment overrides (secrets, paths)
├── pim.yml                  # Project config (serve defaults, iso settings)
├── data/                    # YAML declarations (what to build)
│   ├── builds/default.yml   # Build recipes (profile + ISO + method)
│   ├── isos/default.yml     # ISO catalog
│   ├── profiles/default.yml # Installation profiles (deep merge from default)
│   └── targets/default.yml  # Deploy targets
├── builders/                # Builder components (how to build)
│   ├── post_installs/default.sh      # Late-command scripts (run during preseed)
│   ├── preseeds/default.cfg.erb      # Preseed templates (ERB)
│   ├── scripts/{base,finalize}.sh    # SSH provisioning scripts (run post-install)
│   └── verifications/default.sh      # Verification scripts (post-build)
\```
```

Also update:
- "Template/Script Naming Convention" section — change directory references
- Any other references to old directory names

### 3. Run full spec suite

```bash
bundle exec rspec
```

All specs must pass green.

### 4. Update state.yml

Add `layout-refactor` tier to `docs/state.yml` and mark plans complete as they finish.

## Test Spec

No new tests — this plan is about cleanup and documentation. The verification is:

1. `grep` returns no old path references in `lib/` or `spec/`
2. `bundle exec rspec` is fully green
3. CLAUDE.md accurately describes the new layout

## Verification

```bash
# No old references remain
grep -rn 'preseeds\.d\|installs\.d\|scripts\.d\|verifications\.d' lib/ spec/ | wc -l
# Should be 0

# All specs green
bundle exec rspec

# Manual: read through CLAUDE.md and verify accuracy
```
