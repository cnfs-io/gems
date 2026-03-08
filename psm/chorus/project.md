---
last_refreshed_at: "2026-02-27T20:05:00Z"
bootstrapped: true
---

# Project Context — PSM

## What It Is

PSM (Product Services Manager) is a Ruby CLI gem for managing containerized services via Podman and systemd. It maintains a curated library of service definitions, wraps third-party compose files into a consistent format, and deploys services as systemd units using Podman quadlets. Sibling to PIM (Product Image Manager) — PIM builds images, PSM runs them.

## Current State

**Pre-implementation.** The gem has been scaffolded via `bundle gem` but contains no functional code. The `Psm` module exists with only a `VERSION` constant and a base `Error` class. No CLI entry point, no commands, no models.

The gemspec still has TODO placeholders for summary, description, homepage, and source URIs. Dependencies (`tilos`, `flat_record`, `activesupport`, `pry`) listed in CLAUDE.md are not yet added to the gemspec.

The sole spec is the default `bundle gem` placeholder (including a deliberately-failing assertion).

## Architecture (Planned)

Full architecture is documented in CLAUDE.md. Key points:

- **Flow:** Service Definition (service.yml) → PSM → Quadlet Unit → systemd + Podman → Running Container
- **CLI Pattern:** tilos REST CLI — resources as nouns, REST verbs as actions
- **Persistence:** FlatRecord with YAML backend for service definitions and deployment state
- **Config:** XDG-compliant paths, project-local `psm.yml` deep-merged over global `~/.config/psm/`
- **Dual mode:** User-mode (rootless Podman, `systemctl --user`) and system-mode (root, `systemctl`)

## File Structure

```
lib/
├── psm.rb              # Module stub (XDG constants, requires — not yet implemented)
└── psm/
    └── version.rb      # 0.1.0
spec/
├── spec_helper.rb
└── psm_spec.rb         # Placeholder only
chorus/
└── units/
    ├── foundation.md   # Unit record (pending)
    └── foundation/     # 3 plans, all pending
```

No `exe/psm`, no commands, no models, no fixtures yet.

## Development Plans

**Foundation tier** — 8 plans total (3 have plan files, 5 more described in the unit README):

| # | Plan | Status |
|---|------|--------|
| 01 | Project scaffold and config | pending |
| 02 | Service model | pending |
| 03 | Fixture services | pending |
| 04 | Import from compose | pending (no plan file yet) |
| 05 | Quadlet builder | pending (no plan file yet) |
| 06 | Deployment model | pending (no plan file yet) |
| 07 | Lifecycle commands | pending (no plan file yet) |
| 08 | Profile model | pending (no plan file yet) |

Plan 01 is the starting point — it establishes the gem entry point, XDG constants, project root detection, config merge, `psm new`, `psm config`, and `psm console`.

## Dependencies

**Runtime (declared in CLAUDE.md, not yet in gemspec):** `tilos`, `flat_record`, `activesupport`, `pry`
**Dev:** `rspec`, `rubocop`, `rake`
**System:** `podman`, `systemctl`
**Ruby:** >= 3.2.0
