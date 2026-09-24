---
status: complete
started_at: "2026-03-17T00:38:19+08:00"
completed_at: "2026-03-17T00:39:33+08:00"
deviations: null
summary: Removed legacy netboot/, notes.txt, main.yml, fixed SSH detect_type constants, removed vestigial compute_ip/storage_ip from Host
---

# Execution Log

## What Was Done

- Removed `netboot/` directory (legacy Jinja2 templates replaced by ERB in `lib/pcs/templates/netboot/`)
- Removed `spec/fixtures/project/sites/main.yml` (legacy config structure unused by current code)
- Removed `notes.txt` (scratch notes — content was feature ideas, not actionable code)
- Fixed `SSH.detect_type` to use correct constants: `Pcs::PveHost`, `Pcs::TruenasHost`, `Pcs::PikvmHost`, `Pcs::RpiHost`
- Removed `compute_ip` and `storage_ip` attributes from Host model (IPs now live on Interface records)
- Removed `compute_ip`/`storage_ip` from FIELDS and MUTABLE_FIELDS constants
- Removed `compute_ip` prompt from `interactive_configure` in HostsCommand (IPs managed via Interface records)
- Removed `field_prompt :compute_ip` from HostsView
- Removed `compute_ip`/`storage_ip` from fixture `sites/sg/hosts.yml`
- Removed `compute_ip` from e2e `test_project.rb` host fixtures

## Test Results

554 examples, 0 failures

## Notes

The `compute_ip` method in `Proxmox::Installer` (line 34) is a local method `def compute_ip = host.ip_on(:compute)` — not the removed attribute. It correctly delegates to Interface records and was left unchanged.

## Context Updates

- `SSH.detect_type` now references correct STI class constants (`Pcs::PveHost`, etc.) instead of nonexistent `Hosts::` namespace.
- Host model no longer has `compute_ip` or `storage_ip` attributes. IP addresses live exclusively on Interface records, accessed via `host.ip_on(:compute)` and `host.ip_on(:storage)`.
- `host update` interactive flow no longer prompts for `compute_ip`. IP management is done through Interface records.
- Legacy files removed: `netboot/` (Jinja2 templates), `notes.txt`, `spec/fixtures/project/sites/main.yml`.
