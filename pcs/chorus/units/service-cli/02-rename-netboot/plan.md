---
---

# Plan 02 — Rename Netbootxyz -> Netboot

## Context

Read before starting:
- `lib/pcs/service/netbootxyz.rb` — the file to rename
- `lib/pcs/cli.rb` — requires the service file
- `lib/pcs/config.rb` — `NetbootxyzSettings` class name and `ServiceSettings#netbootxyz` method
- `lib/pcs/commands/services_command.rb` — references `Service::Netbootxyz`
- `lib/pcs/templates/project/pcs.rb.erb` — `config.service.netbootxyz` block
- `spec/fixtures/project/pcs.rb` — test fixture
- `spec/` — any specs referencing `Netbootxyz`

## Background

The class `Service::Netbootxyz` doesn't match the CLI name `netboot`. This matters because plan-03 introduces convention-based resolution via `Service.const_get(name.capitalize)` — the CLI argument `netboot` must capitalize to `Netboot`, the actual class name. Beyond enabling that convention, `Netboot` is simply a better name — the `xyz` suffix is an implementation detail of which netboot project is used.

## Implementation

### Step 1: Rename the service class file
### Step 2: Rename config settings class
### Step 3: Update all references
### Step 4: Update internal config reads
### Step 5: Clean up

## Verification

```bash
bundle exec rspec
grep -rn "Netbootxyz" lib/ | grep -v "container.*netbootxyz\|podman.*netbootxyz\|image.*netbootxyz"
```

The grep should return empty — `Netbootxyz` only appears in container/image name strings, never as a Ruby class name.
