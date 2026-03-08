---
---

# Refactor Plan 03: Command and Service Specs

## Goal

Add integration-style specs for PCS CLI commands and service classes. These specs exercise the orchestration layer — the code that PCS actually owns — using real FlatRecord persistence against tmpdir fixtures with stubbed adapters.

## Prerequisites

- Plan 01 complete (model specs green)
- Plan 02 complete (FlatRecord migration done, model specs still green)

## Approach

Commands are dry-cli classes with a `call` method. Specs invoke `call` directly (not via shell), capture stdout/stderr, and assert on model state changes and output.

Service classes wrap adapter interactions (SSH, nmap, podman). Stub the adapters, test the orchestration logic.

## Spec Structure

```
spec/pcs/commands/
  device/
    scan_spec.rb
    get_spec.rb
    set_spec.rb
  service/
    get_spec.rb
    set_spec.rb
  site/
    use_spec.rb
spec/pcs/services/
  dnsmasq_service_spec.rb
  netboot_service_spec.rb
  control_plane_service_spec.rb
```

## Shared Setup

All command specs need:
- Tmpdir PCS project (via `create_test_project`)
- FlatRecord configured to point at tmpdir
- `Dir.chdir` into project root
- Captured stdout/stderr (use `StringIO` or RSpec's `output` matcher)
- FlatRecord stores reloaded between examples

## Command Specs

Detailed specs for device/scan, device/get, device/set, service/get, service/set, site/use.

## Service Specs

Detailed specs for dnsmasq_service, netboot_service, control_plane_service with stubbed adapters.

## Verification

```bash
cd ~/.local/share/ppm/gems/pcs
bundle exec rspec spec/pcs/commands/
bundle exec rspec spec/pcs/services/
bundle exec rspec  # full suite
```

All green = Plan 03 complete.

## Notes

- Interactive TTY::Prompt commands are deferred — they need `tty-prompt`'s test mode or input simulation
- Adapter specs are out of scope — they wrap system tools (nmap, SSH, podman) that need real infrastructure
- The service specs may reveal that service classes are too tightly coupled to adapters. If so, note refactoring opportunities but don't act on them — that's a separate effort
