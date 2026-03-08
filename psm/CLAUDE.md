# PSM — Product Services Manager

## What PSM Does

PSM is a Ruby CLI tool for managing containerized services via Podman and systemd. It maintains a curated library of service definitions, wraps third-party compose files into a consistent format, and deploys services as systemd units using Podman quadlets.

PSM is a sibling to PIM (Product Image Manager). PIM builds images; PSM runs them. A PSM-managed service can use any image — from a public registry, from PIM, or built locally.

## Architecture

```
Service Definition (service.yml) → PSM → Quadlet Unit → systemd + Podman → Running Container
```

Compose files (from the internet or hand-crafted) are imported and normalized into PSM service definitions. PSM does not run compose directly — it transforms compose into its own managed format.

## Development Methodology

PSM follows a three-tier maturity model (Foundation → Production → Platform). Plans are in `docs/`. Progress is tracked in `docs/state.yml`. Execution log in `docs/log.yml`.

**Current tier:** Foundation

To build: read `docs/foundation/README.md`, then execute plans sequentially.

## Project-Oriented Design

PSM is project-oriented, following the same pattern as PIM. Configuration merges global (`~/.config/psm/`) over project-local (discovered from `$PWD` upward via `psm.yml`).

A project directory created by `psm new` looks like:

```
myproject/
├── psm.yml                  # Project config
└── services.d/              # Service definitions (one dir per service)
    ├── postgres/
    │   ├── service.yml      # PSM manifest
    │   └── compose.yml      # Optional: upstream compose source for reference
    └── nginx/
        └── service.yml
```

Machine-local data lives in XDG directories:

- `~/.config/psm/services.d/`     — global service library
- `~/.local/share/psm/`           — registry, deployed state, user-mode service files
- `~/.local/share/psm/<name>/`    — per-service data dir (user mode)
- `/opt/psm/<name>/`              — per-service data dir (system mode)
- `~/.cache/psm/compose/`         — cached upstream compose files

## System vs User Services

PSM makes a first-class distinction between deployment modes:

| | User Mode | System Mode |
|---|---|---|
| Podman | rootless | root |
| systemd | user session (`systemctl --user`) | system (`systemctl`) |
| Quadlet path | `~/.config/containers/systemd/` | `/etc/containers/systemd/` |
| Data path | `~/.local/share/psm/<name>/` | `/opt/psm/<name>/` |
| Requires sudo | No | Yes |
| Ansible | invoke as target user | invoke with `become: true` |

Mode is set at deployment time, not in the service definition. The same service.yml can be deployed in either mode.

## REST CLI Pattern

PSM follows the tilos REST CLI pattern — resources are nouns, actions map to REST verbs:

```
psm services list|show|create|edit|delete
psm deployments list|show|create|destroy
psm deployments update <name>        # repull image + restart
psm deployments start|stop|restart <name>
psm profiles list|show|create|apply
psm imports create <path|url>        # ingest compose → service definition(s)
psm config list|get|set
psm console                          # Pry REPL with all Psm:: objects
```

## Service Definition Format (service.yml)

```yaml
name: postgres
image: docker.io/library/postgres:16
source: compose          # or: custom, pim, registry
env:
  POSTGRES_PASSWORD: "{{ secrets.postgres_password }}"
volumes:
  - postgres_data:/var/lib/postgresql/data
ports:
  - "5432:5432"
restart: always
profiles:
  - database
```

`source` is informational — it records where the definition came from, not how it runs.

## Namespace

Everything is flat under `Psm::`:

```
Psm
├── Config               # Unified config — reads psm.yml, merges global + project
├── ServiceConfig        # Loads service definitions from services.d/
├── ServiceManager       # Service library operations (list, show, add, edit)
├── DeploymentManager    # Systemd/quadlet lifecycle
├── QuadletBuilder       # Generates .container / .pod unit files
├── ImportManager        # Compose file ingestion and normalization
├── ProfileManager       # Named service collections
├── Registry             # FlatRecord-backed deployment state
├── Project              # Project scaffolding and root detection
├── CLI                  # tilos CLI registry
└── Commands::           # One file per CLI command
```

## Key Patterns

### Config Merge (same as PIM)
Project config (found by walking up from `$PWD`) deep-merges over global `~/.config/psm/`. Project-level service definitions override global definitions by name.

### FlatRecord for State
`Psm::Registry` uses FlatRecord to persist deployment state — which services are deployed, in which mode, when last updated.

### Quadlet Generation
PSM generates Podman quadlet `.container` files and places them in the appropriate systemd directory based on mode. It then invokes `systemctl [--user] daemon-reload` and `enable`/`start`.

### Ansible Integration
PSM is installable as a gem on remote hosts. Ansible playbooks can invoke `psm deployments create <name>` directly. System-mode operations require `become: true`. User-mode operations do not.

## Fixture Services (for testing)

The following services are included as file-based fixtures in `spec/fixtures/services/`:

| Service | Notes |
|---|---|
| n8n | Single container, good baseline |
| authentik | Multi-container (server + worker + postgres + redis) — see open question below |
| home_assistant | System mode candidate; host networking, possible device access |
| nextcloud | Single image (`nextcloud:stable`), expects external reverse proxy |
| traefik | Paired with docker-socket-proxy — see open question below |
| cloudflared | Single container, outbound-only tunnel, minimal config |

### Open Question: Pods vs Linked Services

Authentik and Traefik+socket-proxy are inherently multi-container. PSM must decide:

- **Pod model** — tightly-coupled containers are declared as a single `pod` resource (maps to Podman pod + quadlet `.pod` file). The pod is the deployment unit.
- **Linked services model** — each container is its own PSM service with declared dependencies. Deployment order is resolved by PSM.
- **Hybrid** — pods for tightly-coupled (authentik), linked services for loosely-coupled co-deployments.

This decision shapes the manifest format and the `psm deployments` resource significantly. It should be addressed in the plan that implements multi-container support.

## Dependencies

Ruby gems: `tilos`, `flat_record`, `activesupport`, `pry`
Dev gems: `rspec`, `rspec-mocks`
System: `podman`, `systemctl`

## Testing

- **Unit tests:** `bundle exec rspec` — config, service definitions, quadlet generation, import normalization, CLI routing
- **Fixture-based:** `spec/fixtures/services/` — one directory per fixture service with realistic `service.yml` and where applicable a source `compose.yml`
- **Integration tests:** `bundle exec rspec --tag integration` — requires Podman + systemd
