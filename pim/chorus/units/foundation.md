---
objective: "Correctness — does PIM build verified images from a project directory?"
status: complete
---

# Foundation Tier

**Objective:** Correctness — does PIM build verified images from a project directory?

The Foundation tier establishes PIM as a project-oriented tool with a clean data model and consistent CLI API.

## Read first

Before implementing any plan:

1. **`CLAUDE.md`** (project root) — architecture overview, QEMU conventions, code layout
2. The plan's **Context** section — lists specific files to read

## Plans

| Plan | Name | Depends On | Key Deliverables |
|------|------|------------|------------------|
| 01 | RSpec and ActiveSupport | — | RSpec setup, replace DeepMerge, unit specs |
| 02 | Project structure | 01 | `pim new`, project directory conventions |
| 03 | Dry::CLI migration | 02 | Replace Thor with Dry::CLI, one-file-per-command |
| 04 | Namespace, Config, Console | 03 | Flatten under `Pim::`, unified Config, `pim console`/`pim c` |
| 05 | Ventoy self-managed download | 04 | Auto-download Ventoy binaries, shared HTTP module |
| 06 | FlatRecord integration | 05 | Profile/Iso FlatRecord models, `get` API, drop `.d/` pattern |
| 07 | Build model and parent_id | 06, FR ext-01 | Build recipe model, Profile `parent_id` inheritance chains |
| 08 | Target model with STI | 07, FR ext-02 | Target base + subclasses (local, proxmox, aws, iso) |

**FlatRecord dependencies:**
- Plan 07 requires FlatRecord extension `plan-01-read-only-multi-path` (already complete if plan 06 ran)
- Plan 08 requires FlatRecord extension `plan-02-sti`

## Completion criteria

Foundation is complete when:

- `pim new myproject` scaffolds a working project directory
- `pim console` starts a Pry REPL with all models accessible
- Profile inheritance via `parent_id` resolves through chains
- Build model joins profile + ISO + distro/automation/target
- Target model uses STI (local, proxmox, aws, iso subtypes)
- Uniform `get [ID] [FIELD]` API across profile, iso, build, target
- All data models are FlatRecord-backed with global+project merge
- `rspec` passes all unit specs

