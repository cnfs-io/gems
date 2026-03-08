---
objective: "Correctness — does PSM manage a curated service library and deploy services consistently via Podman quadlets?"
status: pending
---

# Foundation Tier

**Objective:** Correctness — does PSM manage a curated service library and deploy services consistently via Podman quadlets?

The Foundation tier establishes PSM as a project-oriented tool with a clean data model, consistent REST CLI API, and a working deploy/undeploy cycle for both user and system mode.

## Read first

Before implementing any plan:

1. **`CLAUDE.md`** (project root) — architecture overview, conventions, namespace
2. The plan's **Context** section — lists specific files to read

## Plans

| Plan | Name | Depends On | Key Deliverables |
|------|------|------------|------------------|
| 01 | Project scaffold and config | — | `psm new`, XDG dirs, Config merge (global + project) |
| 02 | Service model | 01 | `Psm::Service` FlatRecord model, `services.d/` resolution, `psm services list\|show` |
| 03 | Fixture services | 02 | File-based fixtures: n8n, authentik, home_assistant, nextcloud, traefik, cloudflared |
| 04 | Import from compose | 02 | `psm imports create`, compose → service.yml normalization |
| 05 | Quadlet builder | 02 | `Psm::QuadletBuilder`, `.container` file generation, user vs system paths |
| 06 | Deployment model | 05 | `Psm::Registry` (FlatRecord), `psm deployments create\|destroy\|list\|show` |
| 07 | Lifecycle commands | 06 | `psm deployments start\|stop\|restart\|update`, systemctl wrappers |
| 08 | Profile model | 06 | `Psm::Profile`, `psm profiles list\|show\|create\|apply` |

## Completion criteria

Foundation is complete when:

- `psm new myproject` scaffolds a working project directory
- `psm console` starts a Pry REPL with all `Psm::` objects accessible
- Global (`~/.config/psm/`) and project-local (`services.d/`) definitions merge correctly, project wins on name collision
- `psm services list|show` displays the curated service library
- `psm imports create <path>` ingests a compose file and produces a `service.yml`
- `psm deployments create <n> [--mode system|user]` generates a quadlet unit and enables it via systemd
- `psm deployments destroy <n>` disables and removes the unit
- `psm deployments start|stop|restart|update` wrap systemctl correctly for both modes
- `psm profiles apply <n>` deploys all services in a profile
- Deployment state persisted via FlatRecord registry
- `rspec` passes all unit specs with fixture-based service definitions
