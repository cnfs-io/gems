---
objective: "Promote 'run a VM from a built image' into a first-class pim vm command set."
status: complete
---

# VM Runner — Run and Manage VMs from Built Images

## Objective

Promote "run a VM from a built image" from the ad-hoc `build verify --console` path into a first-class `pim vm` command set. This supports interactive development, script-based provisioning, and long-running VMs with bridged networking.

## Background

Today the only way to boot a built image is `pim build verify <id> --console`, which is a verification tool repurposed for interactive use. It always uses user-mode networking (hostfwd), always uses `-snapshot`, and the boot logic is inlined in `BuildsCommand::Verify#boot_interactive`.

The new `pim vm` namespace treats VMs as ephemeral runtime objects with proper lifecycle management: run, list, stop, ssh, with support for bridged networking, CoW overlays, and script-based provisioning.

## Architecture

### Runtime state

VM instances are tracked in `$XDG_RUNTIME_DIR/pim/vms/` (falls back to `/tmp/pim/vms/` on macOS). Each running VM gets a YAML state file:

```yaml
# ~/.local/state/pim/vms/default-arm64.yml (or /tmp/pim/vms/...)
pid: 12345
build_id: default-arm64
image_path: /home/user/.local/share/pim/vms/default-arm64.qcow2
ssh_port: 2222              # user-mode only
network: user               # or "bridged"
bridge_ip: null              # populated for bridged, discovered via guest agent
snapshot: false
started_at: "2026-02-25T10:00:00Z"
name: default-arm64
```

### Image management

- **Snapshot mode** (default): boots with QEMU's `-snapshot` flag, no disk changes persist
- **Persistent mode** (`--no-snapshot`): creates a CoW overlay via `qemu-img create -b <golden> -F qcow2 -f qcow2` in `~/.local/share/pim/vms/`, boots from overlay
- **Clone mode** (`--clone`): full independent copy via `qemu-img convert` into `~/.local/share/pim/vms/`

### Networking

- **User mode** (default): `hostfwd=tcp::<port>-:22`, SSH via `localhost:<port>`
- **Bridged mode** (`--bridged`):
  - macOS: `vmnet-bridged` on `en0` (requires `sudo`, QEMU runs as root)
  - Linux: tap device attached to a bridge (e.g., `br0`), requires `sudo` for tap creation
  - VM gets a LAN IP, SSH directly to that IP

### Key services

| Class | Responsibility |
|-------|---------------|
| `Pim::VmRunner` | Orchestrates boot: image resolution, overlay creation, QEMU command assembly, VM start |
| `Pim::VmRegistry` | Tracks running VMs via state files in runtime dir, PID liveness checks |
| `Pim::QemuCommandBuilder` | Extended with `add_bridged_net` for bridged networking |
| `Pim::QemuDiskImage` | Already has overlay/clone support (verify what methods exist) |

## Command API

```
pim vm run <build_id>           # Boot a VM from a built image
pim vm list                     # List running VMs
pim vm stop <name>              # Graceful shutdown of a running VM
pim vm ssh <name>               # SSH into a running VM
```

## Plan Table

| # | Plan | Description | Depends on |
|---|------|-------------|------------|
| 01 | vm-run | `VmRunner` service, `vm run` command with user-mode networking, snapshot/overlay/clone | — |
| 02 | bridged-networking | Add bridged networking to `QemuCommandBuilder`, `--bridged` flag on `vm run` | 01 |
| 03 | vm-lifecycle | `VmRegistry`, `vm list`, `vm stop`, `vm ssh` commands | 01 |
| 04 | vm-provisioning | `--run` and `--run-and-stay` script execution via SSH | 01, 03 |

## Completion Criteria

- [ ] `pim vm run default-arm64` boots a VM in snapshot mode with user-mode networking
- [ ] `pim vm run default-arm64 --console` attaches serial console (foreground)
- [ ] `pim vm run default-arm64 --no-snapshot` creates CoW overlay, boots from it
- [ ] `pim vm run default-arm64 --clone` creates full copy, boots from it
- [ ] `pim vm run default-arm64 --bridged` boots with bridged networking (macOS + Linux)
- [ ] `pim vm list` shows running VMs with name, PID, network, SSH info
- [ ] `pim vm stop <name>` gracefully shuts down a running VM
- [ ] `pim vm ssh <name>` opens SSH session to a running VM
- [ ] `pim vm run default-arm64 --run provision.sh` boots, runs script, shuts down
- [ ] `pim vm run default-arm64 --run-and-stay provision.sh` boots, runs script, keeps running
- [ ] Runtime state files cleaned up on stop
- [ ] EFI vars handled correctly for arm64 in all modes

