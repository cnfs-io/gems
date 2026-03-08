---
objective: "Validate the PCS bootstrap pipeline end-to-end: from project scaffold through PXE boot to a running Debian host with verified post-install state."
status: complete
---

# E2E Testing Tier — PCS

## Objective

Validate the PCS bootstrap pipeline end-to-end: from project scaffold through PXE boot to a running Debian host with verified post-install state. Tests run on an isolated virtual network using QEMU, so they can safely execute on production hardware without interfering with live services.

**The question this tier answers:** Does the full PXE boot pipeline actually work — dnsmasq config, netboot menus, preseed, post-install scripts — when a real machine boots from it?

## Constraints

- **Linux only.** QEMU bridge/tap networking requires Linux. macOS lacks the L2 bridge support needed for PXE broadcast. Run these tests on the RPi, a dev VM, or a Linux CI runner — not on a Mac.
- **Requires sudo.** Bridge/tap creation, dnsmasq binding, and QEMU tap attachment all need elevated privileges. The test user must have passwordless sudo for the specific commands used.
- **Isolated network.** All test infrastructure runs on a dedicated bridge (`pcs-test0`) with its own subnet (`10.99.0.0/24`). Production dnsmasq, netboot containers, and VLANs are completely untouched. Two separate L2 domains, no overlap.
- **Debian netinstall, not Proxmox.** The preseed pipeline is the same — Proxmox is installed later via `pcs cluster install`. The e2e validates the netboot → preseed → post-install chain, which is OS-agnostic. Debian netinst is ~400MB vs ~1.2GB for Proxmox ISO and installs in 2-3 minutes vs 10+.

## Architecture

```
pcs-test0 bridge (10.99.0.1/24)
  ├── dnsmasq        — PXE proxy, bound to pcs-test0 only
  ├── netboot (HTTP) — serves iPXE menus, preseed, post-install scripts
  └── QEMU VM        — tap device on pcs-test0, PXE boots
```

All components are created at test start, torn down at test end. The bridge is a standard Linux bridge with an IP assigned; QEMU attaches via a tap device on that bridge. dnsmasq and the netboot HTTP server bind exclusively to the bridge IP, never to `0.0.0.0` or any production interface.

## Network Layout

| Component | IP | Role |
|-----------|-----|------|
| Bridge `pcs-test0` | 10.99.0.1/24 | Gateway, dnsmasq + HTTP bind address |
| QEMU VM | 10.99.0.41 (static via preseed) | Test target host |
| DHCP range | 10.99.0.100–10.99.0.200 | Initial PXE boot (before preseed sets static) |

## Filesystem Layout

All e2e test artifacts live under a single root directory. Nothing is written to the gem directory or to production paths like `/var/lib/pcs/netboot`.

```
/tmp/pcs-e2e/                     # E2E_ROOT — single root for all test artifacts
  project/                        # ephemeral PCS project scaffold
    pcs.rb
    .env
    sites/e2e/
      site.yml
      hosts.yml
    data/
      services.yml
    .ssh/                         # ephemeral SSH keypair
      e2e_key
      e2e_key.pub
      authorized_keys
  netboot/                        # generated boot assets (replaces /var/lib/pcs/netboot)
    menus/                        # TFTP root — iPXE boot files, MAC menus
    assets/                       # HTTP root — preseed, post-install, Debian installer
      pcs/
        preseed.cfg
        authorized_keys
        boot.ipxe
        installs.d/
          e2e-node1.e2e.test.sh
      debian-installer/amd64/
        linux
        initrd.gz
  disk/                           # QEMU qcow2 disk images
    pcs-e2e-node.qcow2
  logs/                           # all log files
    dnsmasq.log
    qemu.log
    http.log
  dnsmasq.conf                    # generated dnsmasq config for test bridge
```

## Prerequisite: Configurable NetbootService

`NetbootService` currently hardcodes `NETBOOT_DIR = Pathname.new("/var/lib/pcs/netboot")`. Plan-01 adds a class-level accessor so the e2e harness (and any future deployment scenario) can redirect output:

```ruby
class NetbootService
  class << self
    attr_writer :netboot_dir

    def netboot_dir
      @netboot_dir || Pathname.new("/var/lib/pcs/netboot")
    end
  end
end
```

All internal references change from `NETBOOT_DIR` to `self.class.netboot_dir` (or `NetbootService.netboot_dir` for class methods). This is a small, backward-compatible change — existing behavior is identical when the accessor is not set.

## Plans

| # | Name | Description | Depends On |
|---|------|-------------|------------|
| 01 | test-harness | Configurable NetbootService, bridge/tap lifecycle, QEMU launcher, SSH wait helper, teardown | — |
| 01b | multi-arch | Architecture-aware QEMU launcher and test project; arm64 (KVM) and amd64 (TCG) support; `--arch` flag | 01 |
| 01c | arch-os-data | Extract arch + OS data to YAML files in `lib/pcs/platform/`; `Platform::Arch` and `Platform::Os` modules; remove e2e `ArchConfig` | 01b |
| 02 | pxe-handshake | Firmware injection in NetbootService + OS YAML; PXE handshake test with QEMU on isolated bridge | 01c |
| 03 | full-install | Complete Debian preseed install, SSH into VM, verify hostname, IP, SSH keys, post-install artifacts | 02 |

## Test Tiers (Runtime Strategy)

The three plans correspond to three test tiers with different execution profiles:

| Tier | What It Validates | Runtime | When to Run |
|------|-------------------|---------|-------------|
| Harness (plan-01) | Bridge, tap, QEMU launch, teardown | ~10s | Always (unit-level) |
| PXE Handshake (plan-02) | dnsmasq serves PXE, VM gets DHCP, downloads iPXE menu | ~30s | On PR / pre-merge |
| Full Install (plan-03) | Preseed completes, post-install runs, SSH verification | ~3-5min | Nightly / manual |

## File Structure

```
spec/
  e2e/
    support/
      arch_config.rb          — architecture configs (amd64, arm64)
      e2e_root.rb             — E2E_ROOT constant + directory helpers
      test_bridge.rb          — bridge + tap create/destroy
      qemu_launcher.rb        — QEMU VM lifecycle (start, wait, kill)
      ssh_verifier.rb         — SSH connect + assertion helpers
      test_project.rb         — scaffold ephemeral PCS project with test data
    pxe_handshake_test.rb     — plan-02: PXE boot reaches DHCP offer
    full_install_test.rb      — plan-03: complete install + verification
    teardown.rb               — standalone cleanup script
```

## Prerequisites

On the test host (RPi or Linux dev VM):

```bash
# Required packages
sudo apt-get install -y qemu-system-x86 dnsmasq-base bridge-utils iproute2

# Verify KVM support (optional but 10x faster)
ls -la /dev/kvm    # should exist on bare metal or nested-virt VMs
```

## Completion Criteria

- `NetbootService.netboot_dir` is configurable (class-level accessor)
- `test/e2e/support/` provides reusable harness classes for bridge, QEMU, SSH
- All test artifacts live under `/tmp/pcs-e2e/` — nothing in the gem dir or production paths
- PXE handshake test proves the dnsmasq + netboot pipeline works on the isolated bridge
- Full install test proves a VM can PXE boot, preseed, run post-install, and be verified via SSH
- All tests are idempotent — can re-run without manual cleanup
- Tests never touch production interfaces, dnsmasq, or netboot containers
- A `bin/e2e` runner script handles the full lifecycle with proper teardown on failure
