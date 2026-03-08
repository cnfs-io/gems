# PIM — Product Image Manager

## What PIM Does

PIM is a Ruby CLI tool that builds VM images from ISOs using QEMU directly. It manages the full lifecycle: ISO catalog → preseed/autoinstall → QEMU build → qcow2 output → verification → deployment to targets.

## Architecture

```
ISO → PIM (Ruby + QEMU) → qcow2 → PIM Verify → PIM Deploy → Targets
```

No Packer. No Ansible at build time. QEMU is invoked directly by PIM's Ruby code. SSH + shell scripts handle post-install provisioning.

## Development Methodology

PIM follows a three-tier maturity model (Foundation → Production → Platform). Plans are in `docs/`. Progress is tracked in `docs/state.yml`. Execution log in `docs/log.yml`.

**Current tier:** Foundation

To build: read `docs/foundation/README.md`, then execute plans sequentially.

## Project-Oriented Design

PIM is project-oriented. All configuration lives in a project directory created by `pim new`:

```
myproject/
├── pim.rb                   # Ruby DSL config (project marker)
├── data/                    # YAML declarations (what to build)
│   ├── builds/              # Build recipes (profile + ISO + method)
│   ├── isos/                # ISO catalog
│   ├── profiles/default.yml # Installation profiles (deep merge from default)
│   └── targets/local.yml    # Deploy targets
├── resources/               # Builder components (how to build)
│   ├── post_installs/default.sh      # Late-command scripts (run during preseed)
│   ├── preseeds/default.cfg.erb      # Preseed templates (ERB)
│   ├── scripts/{base,finalize}.sh    # SSH provisioning scripts (run post-install)
│   └── verifications/default.sh      # Verification scripts (post-build)
```

Data files use FlatRecord's individual layout — one YAML file per record (e.g., `data/profiles/default.yml` contains a single profile hash). Add more records by creating additional `.yml` files in the same directory.

Machine-local data remains in XDG directories:

- `~/.local/share/pim/images/` — built qcow2 images + EFI vars
- `~/.local/share/pim/registry.yml` — image tracking
- `~/.cache/pim/isos/` — downloaded ISOs

## Commands

- `pim new [NAME]` — scaffold a new project
- `pim console` / `pim c` — Pry REPL with project context (all `Pim::` objects accessible)
- `pim iso list|download|verify|add` — ISO catalog management
- `pim profile list|show|add` — profile management
- `pim serve [PROFILE]` — WEBrick preseed/autoinstall server
- `pim build run|list|show|clean|status` — build and manage VM images
- `pim verify PROFILE` — boot image, run verification script, report pass/fail
- `pim config list|get` — configuration management
- `pim ventoy prepare|copy|status|config` — Ventoy USB management

## Boot and Config

### Boot Sequence
`Pim.boot!` is the single entry point that:
1. Finds the project root by walking up from `Dir.pwd` looking for `pim.rb`
2. `load`s `pim.rb` (executes the `Pim.configure` block)
3. Calls `configure_flat_record!` to set up FlatRecord data paths

Boot is called automatically by `Pim.run` for all commands except `new` and `version`.

### Ruby Config DSL
`pim.rb` replaces the old `pim.yml`. Configuration uses a Ruby DSL:

```ruby
Pim.configure do |config|
  config.memory = 4096
  config.serve_port = 9090
  config.iso_dir = ENV.fetch("PIM_ISO_DIR", "~/.cache/pim/isos")

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

`BuildConfig` and `VentoyConfig` delegate to `Pim.config` and accept per-build overrides.

## Namespace

Everything is flat under `Pim::` — no nested modules. This makes all classes directly accessible in `pim console` (Pry on the `Pim` module):

```
Pim
├── Config                   # Ruby DSL config object (populated by pim.rb)
├── VentoySettings           # Nested config for Ventoy (accessed via config.ventoy)
├── Profile                  # Profile model (FlatRecord, parent chain, template resolution)
├── Iso                      # ISO model (FlatRecord)
├── Build                    # Build recipe model (FlatRecord)
├── Target                   # Target model (FlatRecord, STI base)
├── LocalTarget              # Target STI: local QEMU
├── ProxmoxTarget            # Target STI: Proxmox VE
├── AwsTarget                # Target STI: AWS
├── IsoTarget                # Target STI: ISO output
├── BuildConfig              # Build settings — delegates to Pim.config with overrides
├── BuildManager             # Build orchestration
├── LocalBuilder             # Local QEMU build pipeline
├── ArchitectureResolver     # Host/target arch detection and routing
├── CacheManager             # Content-based build cache keys
├── ScriptLoader             # Provisioning script resolution
├── Registry                 # Image registry
├── VentoyConfig             # Ventoy config — delegates to Pim.config.ventoy
├── VentoyManager            # Ventoy operations
├── QemuCommandBuilder       # QEMU command construction
├── QemuVM                   # QEMU VM lifecycle
├── QemuDiskImage            # qemu-img operations
├── Qemu                     # Utility module (find_available_port, etc.)
├── SSHConnection            # SSH/SCP wrapper
├── Server                   # WEBrick preseed server
├── CommandError             # Exception for command failures (console-safe)
├── New::Scaffold            # Project scaffolding (used by pim new)
├── CLI                      # Dry::CLI registry
└── Commands::               # One file per CLI command
```

## QEMU Runtime Conventions

### Sockets and State
All runtime state lives in `$XDG_RUNTIME_DIR/pim/` (falls back to `/tmp/pim/` on macOS):
- `<n>.qmp` — QMP control socket
- `<n>.ga` — guest agent socket (virtio-serial)
- `<n>.serial` — serial console socket (headless mode only)
- `<n>.pid` — QEMU process PID
- `<n>.log` — QEMU stdout/stderr

### Root Ownership
When using `--bridged` (vmnet-bridged), QEMU runs as root via sudo. All sockets, pidfiles, and the QEMU process are root-owned. All queries (QMP, guest agent, pid checks) require `sudo`.

### Guest Agent
Images include `qemu-guest-agent`. The host connects via a virtio-serial channel named `org.qemu.guest_agent.0`. The agent needs ~1 second to respond — socat queries must include a sleep:
```bash
(echo '{"execute":"guest-info"}'; sleep 1) | sudo socat - UNIX-CONNECT:/tmp/pim/<n>.ga
```

### Headless vs Console Mode
- Default: headless with `-display none`, serial on a socket, `nohup` backgrounded
- `--console`: `-nographic`, foreground, serial on terminal
- macOS caveat: cannot use QEMU's `-daemonize` flag with vmnet-bridged due to ObjC runtime fork() crash

### Networking
- `--bridged`: vmnet-bridged on en0, VM gets LAN IP (requires sudo)
- Default: user-mode with `hostfwd=tcp::<port>-:22`

## Code Organization

```
lib/pim.rb                             # Main module, Server, XDG constants, boot dispatch
lib/pim/
├── boot.rb                            # Pim.root, Pim.root!, Pim.boot!, Pim.reset!
├── config.rb                          # Pim::Config DSL, VentoySettings, Pim.configure
├── cli.rb                             # Dry::CLI registry
├── models.rb                          # FlatRecord configuration, model requires
├── models/
│   ├── profile.rb                     # Profile (FlatRecord, template resolution)
│   ├── iso.rb                         # Iso (FlatRecord)
│   ├── build.rb                       # Build (FlatRecord)
│   └── target.rb                      # Target (FlatRecord, STI)
├── services/
│   ├── build_config.rb                # BuildConfig (delegates to Pim.config)
│   ├── architecture_resolver.rb       # Arch detection and builder routing
│   ├── cache_manager.rb               # Build cache keys
│   ├── script_loader.rb               # Script resolution from resources/scripts/
│   ├── ventoy_config.rb               # VentoyConfig (delegates to Pim.config.ventoy)
│   ├── ventoy_manager.rb              # Ventoy operations
│   ├── registry.rb                    # Image registry
│   ├── verifier.rb                    # Image verification
│   ├── qemu.rb                        # QEMU utilities
│   ├── qemu_disk_image.rb             # qemu-img operations
│   ├── qemu_command_builder.rb        # QEMU command construction
│   ├── qemu_vm.rb                     # QEMU VM lifecycle
│   ├── ssh_connection.rb              # SSH/SCP wrapper
│   └── http.rb                        # HTTP download utilities
├── build/
│   ├── local_builder.rb               # Local QEMU build pipeline
│   └── manager.rb                     # Build orchestration
├── new/
│   ├── scaffold.rb                    # Pim::New::Scaffold (project creation)
│   └── template/                      # Template files for pim new
│       ├── pim.rb                     # Ruby DSL config template
│       ├── data/                      # Data directory templates
│       └── resources/                 # Resource templates
├── views/                             # RestCli views
└── commands/                          # One file per CLI command
    ├── new.rb
    ├── console.rb
    ├── serve.rb
    ├── version.rb
    ├── profiles_command.rb
    ├── isos_command.rb
    ├── builds_command.rb
    ├── targets_command.rb
    ├── ventoy_command.rb
    └── config_command.rb
```

## Key Patterns

### Boot
`Pim.boot!` is the centralized boot entry point. It's called once at CLI startup via `Pim.run`. Commands that don't need a project (`new`, `version`) are skipped.

```ruby
Pim.boot!(project_dir: "/path/to/project")  # explicit
Pim.boot!                                    # auto-detect from Dir.pwd
```

### Ruby Config DSL
`Pim.configure` populates `Pim.config` (a `Pim::Config` instance). The `pim.rb` file in the project root calls `Pim.configure` with a block. `BuildConfig` and `VentoyConfig` delegate to `Pim.config` for defaults.

### Deep Merge from Default
Profile data is merged via parent chain using `Hash#deep_merge`. Child fields override parent fields.

### Template/Script Naming Convention
Files match profile name with fallback to `default`:
- `resources/preseeds/developer.cfg.erb` → fallback `resources/preseeds/default.cfg.erb`
- `resources/scripts/developer.sh` → fallback `resources/scripts/default.sh`
- `resources/verifications/developer.sh` → fallback `resources/verifications/default.sh`

### Context-Aware Exit
Commands use `Pim.exit!` instead of `exit`. In CLI mode it exits the process. In console mode (`pim console`) it raises `Pim::CommandError` so the REPL stays alive.

### CLI Dispatch from Console
`Pim.run "profile list"` dispatches CLI commands from within the Pry REPL.

### Preseed Server Reuse
`pim build` wraps the existing `Pim::Server` (WEBrick) in a background thread. Do not create a new HTTP server.

## Dependencies

Ruby gems: `dry-cli`, `activesupport`, `pry`, `webrick`, `net-ssh`, `net-scp`
Dev gems: `rspec`, `rspec-mocks`
System: `qemu`, `qemu-img`, `socat` (for socket queries), `bsdtar` (for ISO kernel extraction)

## Testing

- **Unit tests:** `bundle exec rspec` — config, profiles, ISOs, project scaffolding, CLI routing, namespace
- **Integration tests:** `bundle exec rspec --tag integration` — full build+verify cycle (slow, requires QEMU + ISO)
- **BATS tests:** Legacy integration tests in `test/` (kept alongside RSpec)
