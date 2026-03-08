# PIM Backlog

Items captured during planning that aren't yet assigned to a tier.

---

## Zsh command completions

**Target tier:** Platform

Generate zsh completion scripts for all `pim` commands and subcommands. Completions should include subcommands, options/flags, and dynamic completion for IDs where possible (profile names, ISO keys, build IDs, target IDs). Only implement once the CLI API is stable.

Consider: Dry::CLI may have completion generation support or there may be a gem for it. Otherwise, generate a `_pim` completion function from the CLI registry.

**Rationale for deferral:** API is still evolving through Foundation tier. Completions would need constant updating.

---

## `pim vm` CLI subcommand

Port the zsh helpers (`pim-run`, `pim-ps`, `pim-stop`, `pim-console`, etc.) to Ruby as a `pim vm` subcommand. Currently these are macOS-only shell functions — a Ruby implementation would be cross-platform and testable.

**Rationale for deferral:** The zsh helpers work fine for now. This becomes important when PIM is used on Linux or in CI where zsh functions aren't available.

---

## Remote builder

Cross-architecture builds via SSH to a remote QEMU host (e.g., build x86_64 images from an ARM Mac via a Proxmox node). The architecture routing in `Pim::ArchitectureResolver` already has the framework for this.

**Rationale for deferral:** Local builds cover the primary use case. Remote builds need a working remote host and more complex orchestration. Planned for Production tier after build verification is solid.

---

## `pim new --starter` and `--interactive`

**Target tier:** Production

Enhance `pim new` with two flags:

- `--starter` — populates the project with realistic sample data (profiles with inheritance, Debian ISOs for both architectures, build recipes). Starter templates live in `lib/pim/templates/starter/`. A new project with `--starter` is immediately ready for `pim iso download` and `pim build run`.
- `--interactive` — TTY::Prompt walks through creating a personalized initial profile (hostname, username, SSH key URL, timezone, distro preference). Requires `tty-prompt` dependency.

Both can be combined: `pim new myproject --starter --interactive` scaffolds starter data then customizes it.

**Rationale for deferral:** The scaffold and data model need to stabilize first. Starter templates already exist at `lib/pim/templates/starter/` and can be manually copied.

---

## Build caching with content-based keys

`Pim::CacheManager` already generates cache keys from profile data, scripts, and ISO checksums. Wire this up to skip builds when cache is valid.

**Rationale for deferral:** Builds are infrequent enough that cache invalidation complexity isn't worth it yet. Foundation focus is correctness, not speed.
