# ADR-001: SSH + CLI Commands Over Native API Clients

**Status:** Accepted
**Date:** 2026-02-18
**Applies to:** All provider implementations in the `pcs` gem

---

## Context

The `pcs` gem needs to drive two infrastructure systems:

- **Proxmox VE** — hypervisor cluster management
- **TrueNAS SCALE** — NAS storage provisioning

Both systems expose programmatic interfaces. The question is which interface layer to use from Ruby.

### Options considered

**Option A — Native API clients (REST / WebSocket)**
- Proxmox: Faraday against the REST API (`https://node:8006/api2/json/`)
- TrueNAS: Custom WebSocket JSON-RPC 2.0 client (no suitable Ruby gem exists; official client is Python-only)

**Option B — SSH + CLI commands**
- Proxmox: SSH to node, run `pvesh` (the Proxmox CLI, which is a thin wrapper around the same REST API)
- TrueNAS: SSH to NAS, run `midclt` (the TrueNAS CLI, which is a thin wrapper around the same WebSocket API)

---

## Decision

**Use SSH + CLI commands (Option B) for all provider implementations.**

---

## Rationale

### Equivalence

`pvesh` and `midclt` are not separate implementations — they are official CLI wrappers around the exact same API endpoints that a native client would call. The Proxmox documentation explicitly describes `pvesh` as "the command line interface to the Proxmox VE API." `midclt` is pre-installed on every TrueNAS instance and is how TrueNAS itself tests its own API.

There is no loss of capability or fidelity by using the CLI.

### TrueNAS has no viable Ruby client

The official TrueNAS API client is Python-only (`truenas_api_client`). The API is JSON-RPC 2.0 over WebSocket, and no production-ready Ruby gem implements this protocol in a synchronous, CLI-friendly way. Building and owning a custom WebSocket + JSON-RPC client in Ruby is engineering overhead that adds no value for a bootstrap tool.

### Architectural fit

The `pcs` gem already has an SSH adapter (`Adapters::Ssh`) and host strategies that use `ssh.exec!` for host configuration. Using the same pattern for provider operations is consistent, not a workaround.

### Debuggability

Every operation is a shell command that can be run manually for testing or recovery. No abstraction layer to fight. Operators can reproduce any `pcs` operation by hand.

### Scope

For the Cluster Formation tier, the goal is correctness — does the infrastructure come up correctly? The CLI approach reaches this goal with the least code and the fewest dependencies.

---

## Consequences

### Positive
- No additional gem dependencies for provider implementations
- `net-ssh` (already in gemspec) is the only transport needed
- Every provider method is independently testable via SSH
- TrueNAS and Proxmox providers are symmetric in implementation style

### Negative
- SSH connection overhead per operation (acceptable for cluster formation, not for high-frequency polling)
- Return values are strings/JSON that must be parsed, not typed objects
- Error handling requires parsing stderr and exit codes rather than catching typed exceptions

### Mitigations
- Parse JSON output with `JSON.parse` where structured data is needed
- Wrap `ssh.exec!` in a helper that checks exit codes and raises on failure
- Connection reuse within a single operation sequence (one SSH session per node per command group)

---

## Not in scope for this ADR

- Post-MVP: if performance or type safety become priorities, a native Proxmox REST client (Faraday) is straightforward to add. The provider interface remains the same — only the transport changes.
- TrueNAS REST API is deprecated as of 25.04 and will be removed in 26.04. A native Ruby client would require WebSocket JSON-RPC 2.0 regardless.
