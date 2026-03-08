---
last_refreshed_at: "2026-02-27T00:00:00Z"
bootstrapped: true
---

# Project Context — PIM

PIM is a Ruby CLI tool (v0.1.0) that builds VM images from ISOs using QEMU directly — no Packer, no Ansible at build time. It manages the full lifecycle: ISO catalog, preseed/autoinstall generation, QEMU build, qcow2 output, verification, provisioning, and deployment to targets (Proxmox, AWS).

See `CLAUDE.md` for full architecture docs, namespace map, QEMU runtime conventions, and code organization.

## Core Architecture

### Data Models (FlatRecord-backed, YAML collection layout)

- **Profile** — machine provisioning profile (hostname, user, packages, etc.). Supports `parent_id` inheritance chains with deep merge. Template resolution falls back from profile-named to `default`.
- **Iso** — ISO catalog entry with download URL, checksum verification.
- **Build** — build recipe joining profile + ISO + distro/automation/target. Carries per-build settings (memory, cpus, disk_size, ssh_user, ssh_timeout) with defaults.
- **Target** — deploy target with STI: `LocalTarget`, `ProxmoxTarget`, `AwsTarget`, `IsoTarget`. Parent chain support.

### Non-FlatRecord Models

- **Image** — value object for registry entries. Lifecycle statuses: built → verified → provisioned → published. Tracks lineage via `parent_id`, provisioning metadata, deployment history.

### Key Services

- **Registry** — v2 YAML-based image catalog at `~/.local/share/pim/images/registry.yml`. Handles golden images, provisioned overlays, status transitions, deployment tracking. Auto-migrates from v1.
- **LocalBuilder** — QEMU build pipeline: extracts kernel from ISO, starts preseed server, boots QEMU, runs SSH provisioning scripts, produces qcow2.
- **BuildManager** — orchestrates builds: resolves profile/ISO/target, checks cache, delegates to LocalBuilder.
- **VmRunner** — boots VMs from built images with snapshot/overlay/clone modes. Supports user-mode and bridged networking. `--run` executes scripts via SSH.
- **VmRegistry** — tracks running VMs via state files in `$XDG_RUNTIME_DIR/pim/vms/`.
- **QemuCommandBuilder** / **QemuVM** / **QemuDiskImage** — QEMU command construction, VM lifecycle, disk operations.
- **SSHConnection** / **SystemSsh** — SSH/SCP operations for provisioning and VM access.
- **Server** — WEBrick preseed/autoinstall server, reused by build pipeline in background thread.
- **ProxmoxDeployer** / **AwsDeployer** — target-specific deployment implementations.
- **Verifier** — boots image in snapshot mode, runs verification script, reports pass/fail.
- **CacheManager** — content-based build cache keys from profile data + scripts + ISO checksums.
- **ArchitectureResolver** — host/target arch detection and builder routing.

## CLI Commands

8 resource namespaces + 4 standalone commands, registered via `RestCli::Registry`:

| Namespace | Actions |
|-----------|---------|
| profile | list, show, add, update, remove |
| iso | list, show, download, verify, add, update, remove |
| build | list, show, run, clean, status, verify, update |
| target | list, show, add, update, remove |
| ventoy | prepare, copy, status, show, download |
| image | list, show, delete, publish, deploy |
| vm | run, list, stop, ssh |
| config | list, get, set |

Standalone: `new`, `console` (c), `serve` (s), `version`

## Dependencies

**Runtime:** `activesupport`, `dry-cli`, `webrick`, `net-ssh`, `net-scp`, `pry`, `flat_record` (local path gem), `rest_cli` (local path gem)

**Dev:** `rspec`, `rspec-mocks`

**System:** `qemu`, `qemu-img`, `socat`, `bsdtar`

## Project Layout Convention

PIM projects (created by `pim new`) use:
- `pim.rb` — Ruby DSL config (project marker)
- `data/` — YAML collection files (builds.yml, isos.yml, profiles.yml, targets.yml)
- `resources/` — preseeds, post_installs, scripts, verifications

Machine-local state in XDG directories (images, ISOs, registry, runtime).

## Development Status

All 10 units complete (40/40 plans executed):

| Unit | Plans | Focus |
|------|-------|-------|
| foundation | 8 | RSpec, project structure, Dry::CLI, namespace, config, FlatRecord models |
| production | 2 | Build verification, code organization |
| refactor | 3 | RestCli adoption, views, command consolidation |
| shared-profiles | 1 | Shared XDG profile path |
| layout-refactor | 7 | data/ + resources/ separation, boot.rb, Ruby config DSL |
| simplification | 5 | Pathname internals, config cleanup, build model defaults |
| collection-layout | 3 | Collection layout, fixture strategy, e2e build+verify |
| cli-conventions | 1 | CLI registration alignment with PCS patterns |
| vm-runner | 4 | vm run/list/stop/ssh, bridged networking, provisioning |
| image-lifecycle | 6 | Image model, registry v2, publish, deploy to Proxmox/AWS |

## Test Coverage

- **Unit specs:** boot, config, CLI routing, all 4 models, all 4 views, commands (builds, config, image, isos, new, profiles, targets, version, vm), services (qemu_command_builder, qemu_disk_image, registry, vm_registry, vm_runner, deployers), namespace, console, http, verifier, ventoy
- **Integration:** `spec/integration/build_and_verify_spec.rb` — full build+verify cycle (requires QEMU + ISO)
- Run: `bundle exec rspec` (unit), `bundle exec rspec --tag integration` (integration), `bundle exec rspec --tag e2e` (full pipeline)
