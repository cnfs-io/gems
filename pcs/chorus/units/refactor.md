---
objective: "Migrate PCS models to FlatRecord, adopt RestCli, flatten namespaces, and unify Host model with STI."
status: complete
---

# PCS Refactor Tier

## Phase 1: FlatRecord Migration (Complete)

| Plan | Description | Status |
|------|-------------|--------|
| plan-01-rename-and-specs | Rename Inventory -> Device, add RSpec, characterization specs | Complete |
| plan-02-flat-record-migration | Replace models with FlatRecord subclasses, data migration | Complete |

## Phase 2: RestCli Adoption (Complete)

| Plan | Description | Status |
|------|-------------|--------|
| [plan-01-add-rest-cli-and-views](plan-01-add-rest-cli-and-views.md) | Add rest_cli dependency, create Device/Service/Site views | Complete |
| [plan-02-command-consolidation](plan-02-command-consolidation.md) | Restructure all commands into single-file-per-resource convention | Complete |

## Phase 3: Namespace and Model Cleanup

| Plan | Description | Status |
|------|-------------|--------|
| [plan-03-flatten-model-namespace](plan-03-flatten-model-namespace.md) | Move models from `Pcs::Models::*` to `Pcs::*` | Pending |
| [plan-04-host-sti](plan-04-host-sti.md) | Merge Device + Hosts into `Pcs::Host` with STI subclasses | Pending |

## Design References

- [design.md](design.md) — Original FlatRecord migration design doc

## Test Data

Reference PCS project with real data: `~/spikes/rws-pcs/me` (two sites: `rok`, `sg`)

## Execution

Plans are sequential within each phase. Plan 03 must complete before plan 04.
