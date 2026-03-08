---
---

# Plan 03 — Flatten Model Namespace

## Objective

Move all PCS models from `Pcs::Models::*` to `Pcs::*`, harmonizing with PIM and Rails conventions. After this plan, `Pcs::Device`, `Pcs::Service`, `Pcs::Site`, `Pcs::Config`, and `Pcs::State` are the canonical model references throughout the codebase.

## Context

Read before starting:
- `lib/pcs/models/device.rb` — `Pcs::Models::Device`
- `lib/pcs/models/service.rb` — `Pcs::Models::Service`
- `lib/pcs/models/site.rb` — `Pcs::Models::Site`
- `lib/pcs/models/config.rb` — `Pcs::Models::Config`
- `lib/pcs/models/state.rb` — `Pcs::Models::State`
- All command and service files that reference `Models::*`

## Implementation Spec

### Step 1: Update model class definitions

Change the module wrapping from `Pcs::Models` to `Pcs` in each model file. The files stay in `lib/pcs/models/` (the directory is fine — Rails does this too).

### Step 2: Update association references

In each model, update `class_name` strings in associations.

### Step 3-10: Global find-and-replace

Search the entire codebase for `Models::Device`, `Models::Service`, `Models::Site`, `Models::Config`, `Models::State` and replace with the direct class names (`Pcs::Device`, etc.).

### Step 11: Remove Models module

Verify no code references `Pcs::Models` directly.

## Design Notes

- **File locations don't change.** Models stay in `lib/pcs/models/`.
- **Use fully qualified `Pcs::Device` etc.** This is explicit and avoids ambiguity.

## Verification

```bash
grep -r "Models::Device\|Models::Service\|Models::Site\|Models::Config\|Models::State" lib/ spec/
# Should return empty

bundle exec rspec
```
