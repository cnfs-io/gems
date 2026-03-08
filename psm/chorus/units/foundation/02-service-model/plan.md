---
---

# Plan 02 — Service Model

## Goal

Introduce `Psm::Service` as a FlatRecord-backed model representing a curated service definition. Implement `psm services list|show|create|edit|delete` following the tilos REST CLI pattern. Services resolve from both global and project `services.d/` directories, with project definitions winning on name collision.

## Context

Read before implementing:

- `CLAUDE.md` — service.yml format, namespace, config merge pattern
- `docs/foundation/plan-01-scaffold-and-config.md` — completed config layer this builds on
- PIM's `lib/pim/profile.rb` — reference for FlatRecord model + `services.d/` resolution pattern
- FlatRecord docs — multi-path read, record schema

## Deliverables

### 1. `Psm::Service` — FlatRecord model

Each service lives in its own subdirectory under `services.d/`:

```
services.d/
└── postgres/
    ├── service.yml      # PSM manifest (required)
    └── compose.yml      # Upstream source (optional, reference only)
```

`service.yml` schema:

```yaml
name: postgres
image: docker.io/library/postgres:16
source: compose          # compose | custom | pim | registry
description: "PostgreSQL database"
env:
  POSTGRES_PASSWORD: ""  # populated per deployment, not here
volumes:
  - postgres_data:/var/lib/postgresql/data
ports:
  - "5432:5432"
restart: always
profiles:
  - database
```

`Psm::Service` attributes: `name`, `image`, `source`, `description`, `env`, `volumes`, `ports`, `restart`, `profiles`.

### 2. `Psm::ServiceConfig` — multi-path resolution

Searches both:
1. `~/.config/psm/services.d/`
2. `<project_root>/services.d/` (if project found)

Project definitions override global by directory name (service name). Returns merged set. Mirror PIM's profile resolution.

### 3. `psm services` commands

```
psm services list              # table: name, image, source, profiles
psm services show <n>       # full detail view
psm services create <n>     # scaffold services.d/<n>/service.yml, open $EDITOR
psm services edit <n>       # open service.yml in $EDITOR
psm services delete <n>     # remove services.d/<n>/ (with confirmation)
```

`create` writes a template `service.yml` with placeholder values and opens `$EDITOR`. If a project is active, creates in project `services.d/`. Otherwise creates in global.

## File layout after this plan

```
lib/psm/
├── service.rb               # Psm::Service, Psm::ServiceConfig, Psm::ServiceManager
└── commands/
    └── services/
        ├── list.rb
        ├── show.rb
        ├── create.rb
        ├── edit.rb
        └── delete.rb
spec/psm/
├── service_spec.rb
└── fixtures/
    └── services/            # Introduced properly in plan-03; scaffold here
        └── .keep
```

## Tests

- `Psm::ServiceConfig` finds services in global dir
- `Psm::ServiceConfig` finds services in project dir
- `Psm::ServiceConfig` project definition wins over global when same name
- `Psm::Service` parses all fields from `service.yml`
- `Psm::Service` handles missing optional fields gracefully
- `psm services list` outputs one row per service
- `psm services show postgres` displays all fields

## Dependencies introduced

- `flat_record` — model persistence and multi-path resolution
