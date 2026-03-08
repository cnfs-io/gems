# pim — Product Image Manager

A Ruby CLI tool for building, managing, and deploying VM images using QEMU. PIM directly orchestrates QEMU — no Packer, no Ansible at build time. SSH and shell scripts handle post-install provisioning.

## Quick start

```bash
# Install
gem install pim

# Create a project
pim new myproject
cd myproject

# Download an ISO
pim iso download debian-13-amd64

# Build an image
pim build run default

# Verify it works
pim verify default
```

The scaffold creates a working project out of the box with a default profile, two ISOs (amd64 + arm64), and matching build recipes.

## Concepts

PIM uses four models that combine to produce VM images:

**Profile** — what the machine *is*. Users, packages, timezone, SSH keys. Profiles support inheritance via `parent_id` so you can layer `dev` -> `dev-roberto` without duplication.

**ISO** — the source media. A catalog of installation ISOs with download URLs and checksums.

**Build** — the recipe. Joins a profile with an ISO, specifies the distro family and automation format (preseed, kickstart), and defines how to build.

**Target** — where the result goes. Local disk, Proxmox cluster, AWS, or repacked ISO. Targets support STI (single table inheritance) for type-specific attributes.

## Project structure

Run `pim new myproject` to scaffold:

```
myproject/
├── pim.rb                         # Ruby DSL config (project marker)
├── data/                          # YAML declarations (what to build)
│   ├── builds.yml                 # Build recipes
│   ├── isos.yml                   # ISO catalog
│   ├── profiles.yml               # Installation profiles
│   └── targets.yml                # Deploy targets
└── resources/                     # Builder components (how to build)
    ├── post_installs/default.sh   # Late-command scripts (run during preseed)
    ├── preseeds/default.cfg.erb   # Preseed templates (ERB)
    ├── scripts/base.sh            # SSH provisioning scripts (post-install)
    ├── scripts/finalize.sh
    └── verifications/default.sh   # Verification scripts (post-build)
```

Data files use FlatRecord's collection layout — one YAML file per model containing an array of records. Add records by appending to the array.

Machine-local data remains in XDG directories:

- `~/.local/share/pim/images/` — built qcow2 images + EFI vars
- `~/.local/share/pim/registry.yml` — image tracking
- `~/.cache/pim/isos/` — downloaded ISOs

## Commands

### Project

```bash
pim new NAME                       # Scaffold a new project
pim console                        # Pry REPL with all models loaded (alias: pim c)
pim version                        # Print version
```

### Profiles

```bash
pim profile list                   # List all profiles
pim profile show ID                # Show profile details (resolved through parent chain)
pim profile add                    # Interactively add a profile
```

### ISOs

```bash
pim iso list                       # List all ISOs
pim iso show ID                    # Show ISO details
pim iso download ID                # Download an ISO (cached in ~/.cache/pim/isos/)
pim iso verify ID                  # Verify checksum (supports inline checksum or checksum_url)
```

### Builds

```bash
pim build list                     # List all build recipes
pim build show ID                  # Show build recipe details
pim build status                   # Show build system status and cached images
pim build clean                    # Clean cached images (--orphaned or --all)
```

#### Building images

```bash
pim build run ID                   # Build an image
pim build run ID --force           # Rebuild ignoring cache
pim build run ID --dry-run         # Show what would happen without building
pim build run ID --console         # Stream serial console to stdout (foreground)
pim build run ID --console-log FILE  # Log serial console to file (background)
pim build run ID --vnc 1           # Enable VNC display on port 5901
```

The `--console` flag runs QEMU in the foreground with serial output on your terminal — useful for watching the installation live. `--console-log` runs in the background but captures all serial output to a file you can `tail -f`.

#### Verifying images

```bash
pim build verify ID                # Boot image in snapshot mode, run verification script
pim build verify ID -v             # Verbose — show verification script output
pim build verify ID --console-log FILE  # Capture serial console to file for debugging
pim build verify ID --console      # Boot interactively for manual debugging
pim build verify ID --ssh-timeout 60    # Custom SSH wait timeout (default: 300s)
pim verify ID                      # Shorthand (alias for build verify)
```

Verification boots the image with QEMU's `-snapshot` flag (no writes to the original image), SSHes in, uploads and runs the verification script, and reports pass/fail.

**Debugging a failed verification:**

If SSH fails to connect during verification, use `--console-log` to capture the boot output:

```bash
pim build verify default --console-log console.log
# In another terminal:
tail -f console.log
```

For interactive debugging, use `--console` to get a serial terminal:

```bash
pim build verify default --console
# Login at the prompt, then:
journalctl -u ssh.service
systemctl status ssh
# Ctrl+A X to quit QEMU
```

### Targets

```bash
pim target list                    # List deploy targets
pim target show ID                 # Show target details
```

### Ventoy USB

```bash
pim ventoy prepare DEVICE          # Format USB with Ventoy
pim ventoy copy                    # Copy ISOs to Ventoy USB
pim ventoy status                  # Show Ventoy USB status
pim ventoy config                  # Show Ventoy configuration
pim ventoy download                # Download Ventoy release
```

### Configuration

```bash
pim config list                    # List all config
pim config get KEY                 # Show specific setting
pim config set KEY VALUE           # Update setting
```

### Preseed server

```bash
pim serve                          # Start WEBrick preseed/autoinstall server
pim serve --port 9090              # Custom port
```

## Configuration

Project configuration uses a Ruby DSL in `pim.rb`:

```ruby
Pim.configure do |config|
  config.memory = 4096
  config.serve_port = 9090

  config.ventoy do |v|
    v.version = "1.0.99"
    v.device = "/dev/sdX"
  end
end
```

Access config anywhere via `Pim.config`:

```ruby
Pim.config.memory         # => 4096
Pim.config.ventoy.version # => "1.0.99"
```

## Profile inheritance

Profiles inherit from other profiles using `parent_id`. Child fields override parent fields:

```yaml
# data/profiles.yml
- id: default
  hostname: debian
  username: ansible
  password: changeme
  locale: en_US.UTF-8
  timezone: UTC
  packages: openssh-server curl sudo qemu-guest-agent

- id: dev
  parent_id: default
  packages: openssh-server curl sudo qemu-guest-agent vim git build-essential

- id: dev-roberto
  parent_id: dev
  authorized_keys_url: https://github.com/rjayroach.keys
  timezone: Asia/Singapore
```

Querying `dev-roberto` resolves the full chain: `default` -> `dev` -> `dev-roberto`.

## Build pipeline

The build pipeline for a local QEMU build:

```
 1. Create qcow2 disk image
 2. Extract kernel/initrd from ISO (direct boot, bypasses GRUB)
 3. Start preseed server (WEBrick)
 4. Boot QEMU with installer kernel + preseed URL
 5. Wait for install to complete (VM powers off)
 6. Boot VM from installed disk
 7. Wait for SSH
 8. Run provisioning scripts (resources/scripts/) over SSH
 9. Finalize image (clean cloud-init, regenerate SSH host keys, truncate machine-id)
10. Shutdown VM
11. Register image in registry
```

Built images are cached by content hash. Subsequent builds with the same profile, scripts, and ISO hit the cache and return immediately. Use `--force` to bypass the cache.

## Architecture

```
ISO -> PIM (Ruby + QEMU) -> qcow2 -> Verify -> Deploy -> Targets
```

PIM produces qcow2 as a universal intermediate format. Images include qemu-guest-agent for deploy-time management. The same image can be deployed to Proxmox, converted to an AMI for AWS, or used locally.

All models are backed by [FlatRecord](https://github.com/rjayroach/flat_record) — ActiveModel-compliant CRUD against YAML files. Models are read-only in the CLI; edit the YAML files directly.

## Dependencies

- **Ruby** >= 3.1
- **QEMU** — `brew install qemu` (macOS) or `apt install qemu-system` (Linux)
- **bsdtar** — for extracting kernel/initrd from ISOs (`brew install libarchive` on macOS, usually pre-installed on Linux)

## License

MIT
