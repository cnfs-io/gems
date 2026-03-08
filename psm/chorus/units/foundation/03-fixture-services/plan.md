---
---

# Plan 03 — Fixture Services

## Goal

Populate `spec/fixtures/services/` with realistic, curated service definitions for all six fixture services. These fixtures serve as both test data and the seed of PSM's real-world service library. Each fixture should be accurate enough to actually work when deployed.

## Context

Read before implementing:

- `CLAUDE.md` — service.yml schema, fixture service list and notes
- `docs/foundation/plan-02-service-model.md` — Service model this builds on
- Upstream compose files for each service (links below)

## Fixture Services

### n8n

Single container. Workflow automation.

- Image: `docker.io/n8nio/n8n:latest`
- Source: compose (from n8n docs)
- Volumes: n8n_data
- Ports: 5678
- Env: `N8N_HOST`, `N8N_PORT`, `N8N_PROTOCOL`, `WEBHOOK_URL`
- Profiles: automation

### authentik

Multi-container: server + worker share same image; require postgres + redis.

- Image: `ghcr.io/goauthentik/server:latest` (server and worker)
- Source: compose (from goauthentik.io)
- **Open question:** modeled as a pod or as linked services? See `CLAUDE.md`.
- For this plan: create a `service.yml` that documents the multi-container nature and records the open question inline as a `# TODO` comment. Do not attempt to resolve it.
- Volumes: postgres_data, redis_data, authentik_media, authentik_certs
- Profiles: auth, infrastructure

### home_assistant

Single container. Strong candidate for system mode (host networking, device access).

- Image: `ghcr.io/home-assistant/home-assistant:stable`
- Source: compose
- Network: host (note in service.yml)
- Volumes: ha_config
- Ports: none (host networking)
- Env: `TZ`
- Preferred mode: system (document in service.yml as `preferred_mode: system`)
- Profiles: home, iot

### nextcloud

Single image. Expects external reverse proxy — no 80/443 exposure at the service level.

- Image: `docker.io/library/nextcloud:stable`
- Source: registry
- Volumes: nextcloud_data, nextcloud_apps, nextcloud_config
- Ports: 8080 (internal only, no host binding in default definition)
- Env: `NEXTCLOUD_ADMIN_USER`, `NEXTCLOUD_ADMIN_PASSWORD`, `NEXTCLOUD_TRUSTED_DOMAINS`
- Profiles: productivity, storage

### traefik

Paired with `docker-socket-proxy` for security. Reverse proxy / ingress.

- Image: `docker.io/traefik:latest`
- Source: compose
- **Open question:** same pod/linked-services question as authentik. Document as `# TODO`.
- Volumes: traefik_certs, `/etc/traefik`
- Ports: 80, 443, 8080 (dashboard)
- Env: none (config file driven)
- Preferred mode: system
- Profiles: infrastructure, ingress

Socket proxy companion:
- Image: `docker.io/tecnativa/docker-socket-proxy:latest`
- Purpose: expose only safe Docker/Podman API endpoints to Traefik

### cloudflared

Single container. Outbound-only Cloudflare tunnel.

- Image: `docker.io/cloudflare/cloudflared:latest`
- Source: registry
- Volumes: none (stateless)
- Ports: none (outbound only)
- Env: `TUNNEL_TOKEN`
- Profiles: infrastructure, networking

## File layout after this plan

```
spec/fixtures/services/
├── n8n/
│   ├── service.yml
│   └── compose.yml          # upstream source, trimmed/annotated
├── authentik/
│   ├── service.yml          # with TODO re: pod vs linked services
│   └── compose.yml
├── home_assistant/
│   ├── service.yml          # preferred_mode: system noted
│   └── compose.yml
├── nextcloud/
│   └── service.yml          # no compose.yml — direct registry image
├── traefik/
│   ├── service.yml          # with TODO re: socket proxy pairing
│   └── compose.yml
└── cloudflared/
    └── service.yml          # minimal, no compose.yml needed
```

## Tests

- All six fixtures load without error via `Psm::Service`
- All required fields (`name`, `image`, `source`) present in every fixture
- Optional fields parse correctly where present
- Fixture names match their directory names
- `psm services list` with fixtures dir as services path shows all six

## Notes

The `compose.yml` files in fixtures are reference copies — trimmed to the essentials, annotated with PSM-specific comments. They are not executed by PSM; they document the upstream source that informed the `service.yml`.
