# CLAUDE.md — PCS1 Gem

## Project Overview

PCS1 is a Ruby CLI gem for bootstrapping bare-metal private cloud sites. It runs on a Raspberry Pi control plane and manages the full lifecycle from network discovery through PXE-based OS installation to Proxmox VE cluster formation.

**Gem location:** `~/.local/share/gems/pcs1/`
**Symlink:** `~/.local/share/gems-source/cnfs-io/pcs1/`
**Dependencies:** `~/.local/share/gems-source/rjayroach/{flat_record,rest_cli}`

## Architecture

### Entry point

`lib/pcs1.rb` — requires all dependencies, auto-requires all Ruby files under `lib/pcs1/` via sorted glob. Defines the `Pcs1` module with `root`, `logger`, `configure`, `config`, `site`, `resolve_template`, and `gem_templates`.

### Boot sequence

`exe/pcs1` → `Application.boot!` → resolves `Pcs1.root` (walks up to find `pcs.rb`) → resolves `data_dir` to absolute path via root → calls `super` (RestCli::Application.boot! configures FlatRecord) → loads `pcs.rb` from project root → `Dry::CLI.new(Pcs1::CLI).call`

### Module layout

```
lib/pcs1.rb                    # Main module, auto-require, template resolution, logger
lib/pcs1/
  application.rb               # Boot sequence, config loading
  cli.rb                       # Command registry (Dry::CLI)
  config.rb                    # Config, HostConfig, DnsmasqConfig, NetbootConfig
  platform.rb                  # Platform detection, system_cmd, sudo_write, capture
  platform/linux.rb            # Linux: local_ips via `ip -j addr`, timezones via timedatectl
  platform/darwin.rb           # macOS: local_ips via ifconfig, timezones via zoneinfo
  service.rb                   # Service base class (delegates to Platform)
  version.rb                   # VERSION constant
  models/
    site.rb                    # Singleton per project. reconcile! dispatches to services
    host.rb                    # STI base. State machine, key!, provision!, local?, pxe_target?
    hosts/
      debian_host.rb           # PXE/preseed, nmcli/networkctl networking, generate_install_files
      pikvm_host.rb            # read-only FS key install (rw/super/ro), reboot to provision
      jetkvm_host.rb           # manual key upload via web UI, reboot to provision
      pve_host.rb              # pve_status state machine, install_pve!, create/join cluster
    network.rb                 # nmap scan, merge_results, contains_ip?
    interface.rb               # discovered_ip, configured_ip, reachable_ip
  services/
    dnsmasq.rb                 # DHCP + PXE boot config. Network-first iteration. reconcile!/start!/stop!
    netboot.rb                 # Podman container, PXE file generation. reconcile!/start!/stop!
  commands/
    new.rb                     # Project scaffolding wizard
    console.rb                 # Pry console
    hosts_command.rb           # List/Show/Add/Update/Configure/Provision/Install/Upgrade/Remove
    networks_command.rb        # List/Show/Scan/Add/Update/Remove
    interfaces_command.rb      # List/Show/Add/Update/Remove
    sites_command.rb           # Add/Show/Update
    service_command.rb         # Start/Stop/Status/Restart
    templates_command.rb       # List/Customize/Reset
  views/
    hosts_view.rb              # Columns, detail fields, field prompts for Host
    networks_view.rb           # Columns, detail fields, field prompts for Network
    interfaces_view.rb         # Columns, detail fields, field prompts for Interface
    sites_view.rb              # Columns, detail fields, field prompts for Site
  templates/
    dnsmasq.conf.erb           # Full DHCP + PXE boot config
    debian/
      preseed.cfg.erb          # Automated Debian install
      post-install.sh.erb      # Post-install hook
    proxmox/
      install.sh.erb           # PVE installation script
      create-cluster.sh.erb    # pvecm create
      join-cluster.sh.erb      # pvecm add
    netboot/
      pcs-menu.ipxe.erb        # iPXE boot menu (generic, uses install_entries from host types)
      mac-boot.ipxe.erb        # Per-MAC iPXE chainloader
      custom.ipxe.erb          # netboot.xyz custom hook
```

## Key Patterns

### STI (Single Table Inheritance)

Host uses FlatRecord STI via `sti_column :type`. Subclasses register with `sti_type "debian"`. All hosts share `data/hosts.yml`. The `type` field determines which Ruby class is instantiated on load.

**Adding a new host type:** Create a file in `models/hosts/`, define the class inheriting from `Host`, call `sti_type "typename"`. The auto-require glob picks it up. `Host.valid_types` automatically includes it. The HostsView type selector shows it.

**Changing a host's type:** Use `host.becomes!("proxmox")` (FlatRecord method, follows Rails `becomes!` pattern). Never use `host.update(type: ...)` — STI protection silently resets it.

### State machines

Host base class: `discovered → keyed → configured → provisioned`

DebianHost overrides to allow: `discovered → configured` (skip keyed, keys come from preseed)

PveHost adds a second state machine on `pve_status`: `pending → pve_installed → networks_validated → clustered`

Uses `state_machines-activemodel` gem. Fire events with `host.fire_status_event(:key)`.

### Template resolution

`Pcs1.resolve_template("debian/preseed.cfg.erb")` checks:
1. `<project_root>/templates/debian/preseed.cfg.erb` — project override
2. `<gem>/lib/pcs1/templates/debian/preseed.cfg.erb` — gem default

Operator customizes with `pcs1 template customize <path>`.

### Project root resolution

`Pcs1.root` walks up from `Dir.pwd` looking for `pcs.rb` (the project marker). Falls back to pwd. All path resolution (data dir, templates) uses `Pcs1.root`.

### Service pattern

Both `Dnsmasq` and `Netboot` inherit from `Service` base class. Service delegates `system_cmd`, `capture`, `sudo_write`, `command_exists?` to `Platform`. Services read from `Pcs1.site` and `Pcs1.config` — no constructor arguments, no dependency injection.

`reconcile!` is the key method — called by `Site.reconcile!` when a host transitions to `configured`. Dnsmasq renders config, diffs against disk, restarts only if changed. Netboot regenerates all PXE files.

### Network-first iteration

Dnsmasq builds reservations by iterating `network.interfaces`, not `site.hosts`. This avoids needing to exclude the control plane — every interface with MAC + configured_ip gets a reservation.

`Dnsmasq.ops_ip_for(network)` finds the local host's IP on a given network via `host.local?`. Netboot reuses this.

### Host identity

`host.local?` checks the host's interfaces against `Platform.current.local_ips`. The control plane is identified by "is this host me?" — no role checks needed.

`host.pxe_target?` — `pxe_boot && !local? && !boot_menu_entry.nil?`. Three conditions: operator flag, not local, type supports PXE.

### Credential resolution

`host.connect_user` → `connect_as` field on record → `config.host_defaults[type][:user]`
`host.connect_pass` → `connect_password` field on record → `config.host_defaults[type][:password]`
`host.wait_attempts` → `config.host_defaults[type][:wait_attempts]` → `config.host.wait_attempts`

### Logging

`Pcs1.logger` — Ruby Logger, configurable in `pcs.rb` via `config.log_level` and `config.log_output`. All code uses `Pcs1.logger.info(...)` — no `puts` in models or services.

### Platform

`Platform.current` dispatches on `RUBY_PLATFORM` → Linux or Darwin. Provides `local_ips`, `available_timezones`.

`Platform.system_cmd(cmd)` — executes with logging, optional raise on failure.
`Platform.capture(cmd)` — executes and returns stdout.
`Platform.sudo_write(path, content)` — writes file via `sudo tee`.
`Platform.command_exists?(cmd)` — checks if command is available.

## Data Model

All models are FlatRecord::Base, stored in YAML under `data/`.

```
Site (1 per project)
  ├── has_many :hosts
  └── has_many :networks
        └── has_many :interfaces
              ├── belongs_to :host
              └── belongs_to :network
```

**Site:** name, domain, timezone, ssh_key
**Host:** hostname, role, type (STI), arch, status (state machine), connect_as, connect_password, pxe_boot, site_id
**Network:** name, subnet, gateway, dns_resolvers, primary, site_id
**Interface:** name, mac, discovered_ip, configured_ip, host_id, network_id

## Dependencies

- `flat_record` — flat-file ORM (YAML backend, STI, associations)
- `rest_cli` — CLI framework (command registration, view layer, field prompts)
- `dry-cli` — command routing
- `tty-prompt` — interactive prompts
- `net-ssh` — SSH operations
- `state_machines-activemodel` — state machines on ActiveModel
- `ed25519`, `bcrypt_pbkdf` — SSH key support

## Testing

Run from the gem root:
```
bundle exec rspec
```

For manual testing, create a project and use the console:
```
pcs1 new test
cd test
pcs1 console
```

## Common Tasks

### Adding a new host type

1. Create `lib/pcs1/models/hosts/my_host.rb`
2. Inherit from `Host`, call `sti_type "mytype"`
3. Implement `restart_networking!`
4. Optionally implement `generate_install_files`, `kernel_params`, `boot_menu_entry` (for PXE types)
5. Optionally override state machine transitions
6. Add default credentials to scaffolded `pcs.rb` CONFIG_TEMPLATE in `commands/new.rb`

### Adding a new service

1. Create `lib/pcs1/services/my_service.rb`
2. Inherit from `Service`
3. Implement `reconcile!`, `start!`, `stop!`, `status`
4. Register in `ServiceCommand::SERVICES` hash
5. Add to `Site#reconcile!` if it should auto-reconcile on host configure

### Adding a new template

1. Create the `.erb` file under `lib/pcs1/templates/<type>/`
2. Reference via `Pcs1.resolve_template("type/filename.erb")` or `Service.render_template`
3. It's automatically available in `pcs1 template list` and customizable

### Modifying the config

1. Add field to the appropriate config class in `config.rb`
2. Add commented-out default to `CONFIG_TEMPLATE` in `commands/new.rb`
3. Reference via `Pcs1.config.<section>.<field>`
