# pcs on termino: progress and handoff

Last updated: 2026-09-24. Read this before continuing work on pcs, termino or flat_record.
The approved plan (full evaluation of the old gems, target architecture, build order) is at
`~/.claude/plans/so-we-have-the-squishy-bachman.md`.

## What we're building

- **pcs** runs on a site's control plane (a Raspberry Pi). It takes bare-metal machines from "on the network" to "installed". The first milestone is **a PXE Debian install**; the Proxmox VE upgrade and clustering come after.
- It's a rebuild of the old `pcs.orig/` and `pcs1.orig/` gems (kept for reference) on **termino**, a framework for text-driven apps with CLI, web UI and console, and **flat_record**, the YAML ORM.

Three roles:

| Role | Who | Example |
|---|---|---|
| Termino author (TA) | writes the framework | `termino new`, `termino g scaffold` |
| Gem author (CA) | builds a domain gem on termino | pcs itself (also the `chaos` example gem) |
| Project author (PA) | uses the gem for one site | `pcs new sg` creates the project `sg/` |

## Where things are

| Thing | Path | Notes |
|---|---|---|
| termino | `~/spaces/anfs-io/gems/termino` | Its own git repo (nested in anfs-io/gems, no commits yet): stage with `git -C termino add -A`. Staged, **not committed** |
| flat_record | `~/spaces/rjayroach/gems/flat_record` | Monorepo with rest_cli and pcm. **The user has their own uncommitted work there** (`flat_record/lib/flat_record.rb`, `flat_record/lib/flat_record/project.rb`, many `rest_cli/*` files). Never stage, revert or overwrite it. Our changes are unstaged edits |
| pcs (new) | `~/spaces/cnfs-io/gems/pcs` | In the cnfs-io monorepo; staged, not committed. **The user has uncommitted pim work in the same repo; never stage it** (always `git add -- pcs`) |
| old pcs / pcs1 | `~/spaces/cnfs-io/gems/{pcs.orig,pcs1.orig}` | Reference only. Moved aside by the user |
| chaos (example gem) | `~/spaces/anfs-io/gems/chaos` | Its project: `~/spikes/termino/chaos/frank` |
| pcm | `~/.local/bin/pcm` | Runs compose services from `~/.config/pcm/containers/<svc>/` |
| pcs ppm package | pdt-ppm repo (`git@github.com:maxcole/pdt-ppm`), `packages/pcs` | ppm's clone is at `~/.local/share/ppm/pdt`. **Open question: where the user edits pdt-ppm** (don't edit ppm's clone unless told to). The container definitions are drafted in `pcs/ppm/` (see its README) until then |

**Environment**
- `local-gems build` links gems into `~/.local/share/gems` and puts binstubs on `PATH`; their `lib` directories go on `RUBYLIB`.
- **Re-run it after adding a gem** (the new pcs isn't linked yet). `pcs.orig/` also has a `pcs.gemspec`; the new `pcs` sorts first, so it wins, and the old one is skipped with a warning.
- **Running tests:**
  - termino and flat_record: `bundle exec rake` / `bundle exec rspec` in each gem.
  - pcs: `BUNDLE_GEMFILE=$PWD/Gemfile bundle exec rspec` from `pcs/`. Its Gemfile has path entries for termino and flat_record pointing at the local-gems links.

## Decisions (with the user)

1. **One project per site** (`pcs new sg`). No `site use`, no `.env`.
2. **The web UI does inventory *and* runs operations:** event buttons on the host page, plus a live log of long jobs.
3. **Framework gaps go into termino first,** then pcs builds on them.
4. **The containers (dnsmasq and netboot.xyz) are run by pcm, not pcs.**
   - The pcs ppm package ships the pcm compose definitions (see *Next: container assets*).
   - pcs writes its generated config into pcm's volume directories, configurable in the project's `pcs.rb`, and controls the containers through `pcm`.
   - pcs never runs podman, systemd or sudo for them.
5. **dnsmasq defaults to proxy DHCP** (it answers PXE only; the site's DHCP server keeps handing out addresses). `dhcp` mode with reservations is optional.
6. **Security:**
   - Only public keys are ever served or copied.
   - Passwords only as crypt(3) SHA-512 hashes (`install.password_hash`); key-only login by default.
   - SSH host keys are trusted on first use (TOFU) and pinned in the project's `ssh/known_hosts`.
   - Commands are argv only, never shell strings.
7. **Operations** (`Termino::Operation`) do all side effects, support `--dry-run`, and fire state-machine events. Nothing assigns `status` directly.
8. **Scaffolds are thin:** behaviour lives in termino (`Termino::Resource`, `Termino::Views`); gems override by subclassing.
9. **Data uses one file per record** (`data/hosts/1.yml`), with flat_record's locking and freshness checks.

## Done

### termino (`~/spaces/anfs-io/gems/termino`; 70 examples, rubocop clean)
- **CLI:** `termino new <gem>` and `termino g scaffold <resource> field:type…`.
  - **Where commands appear:** `new` outside a gem; `generate` inside a gem whose gemspec depends on termino.
  - **`new` inside an existing git repo** passes `--no-git`, writes a `.gitignore`, and stages only the gem's own directory.
- **Generated gem:** `app.rb` (`Termino::App`), `settings.rb` (`Termino::Settings` + `Termino::Configurable`), and `cli.rb` (`Termino::Commands.register(self, Mod, new_project: …)`).
- **Project** = a directory with `config.ru`, found by walking up from the current directory (`Termino::Project.root`).
  - **Project commands:** `server` (Puma), `console` (IRB inside the gem's namespace) and, for each resource, `<plural> list|show|add|update|remove` (`--format json`).
  - Outside a project, only `new` is offered.
- **`NewProject`** writes `config.ru`, `data/`, `.gitignore` and `<gem>.rb` settings. A gem subclasses it with a `setup(root, **opts)` hook, run with flat_record and settings pointed at the new project; a failed setup removes the half-made project.
- **Web** (`Termino::App` < Roda):
  - **Security:** sessions (secret in the project's `tmp/`, never written outside a project), route_csrf (the token is injected into every POST `form`/`Form` automatically), and host_authorization (this machine's names and IPs, plus `TERMINO_HOSTS`).
  - **Behaviour:** status_303, flash, CSP and security headers, a heartbeat at `/up`, an exception page in development, and a 404 for `RecordNotFound`.
- **Resources:** `Termino::Resource` (actions plus the hooks `scope`, `find`, `record_params`) with `Termino::Views::{Layout,Index,Show,Form}`; a gem customises a page by subclassing it under its own `Views::`.
- **Tailwind:** `server` builds `public/app.css` with tailwindcss-ruby and keeps a `--watch` process running. It scans the gem's `lib`, termino's `views.rb`, and only the ruby_ui components termino loads.
- **`Termino::Settings`:** typed settings with defaults, which can be computed, grouped, and refer to their parent; overridden in the project's `<gem>.rb`.
- **`Termino::Operation`:** `step "…" { … }`, `dry_run:`, steps recorded as done/planned/failed, failures captured (`call!` raises).
- **`Termino::Command`:** a base for a gem's own commands (`enter_project!`, `run_operation`), with `platforms :linux` gating (aborts elsewhere; inherited).
- **A gem's own project commands:** `Termino::Commands.register(self, Gem) { |r| r.register "networks scan", Scan }`. The block runs only inside a project, and can extend a resource's command group.
- **Resource field types `:select`** (`choices:` array or proc; values or `[label, value]` pairs; shown as labels in pages and CLI) **and `:state`** (a badge coloured by `colors:`; never editable, never a CLI option, never taken from a form).
- **STI-aware resources:** pages and CLI skip fields a record's type lacks. `Resource#build(values)` and `#assign(record, values)` are shared by web and CLI; override `assign` to swap the record's class (pcs does `record.becomes(klass)`).
- **Show pages have a `related` hook** (below the fields). **The layout has a nav bar** of the app's resources.
- **Resource CLI commands have per-resource help** ("List hosts", "Change a host's fields").
- **Subclassing a resource inherits its model, fields, path and read-only flag.** `read_only!` means no new/edit/delete, and only `list`/`show` in the CLI.
- **The layout comes from the app's namespace first**, so termino's own pages (jobs) use the gem's layout.
- **`Operation#wait_for(description, timeout:, interval:) { ... }`**: a polling step that raises `Operation::TimeoutError`. `clock`/`pause` can be overridden in tests.
- **State events:** a record whose `:state` field has a state machine gets a button per event it can fire now (`<field>_events`), posting to `/<path>/:id/events/:event`. `Resource#events`, `#event_label` and `#fire` are hooks; `Views::Show#event_button(event)` can be overridden (e.g. to add a password input). Events it can't fire are refused with a flash.
- **Jobs** (`lib/termino/jobs.rb`): `Termino::Job.start(OperationClass, label:, subject:, args:, secrets:)` runs the operation in a thread of the web server, logging to `<project>/tmp/jobs/<id>.log`.
  - Only `args` (plain values) are saved to `data/jobs/<id>.yml`; **`secrets` never are**.
  - One active job per subject record (`Job::Busy`).
  - `Termino::JobsResource` (read-only, newest first) shows the log. A running job's page reloads itself via the `Refresh` header, so no JS is needed and it's CSP-safe.
  - **When the server starts**, jobs left queued or running become `interrupted`, and the operation class's `interrupted(**args)` hook runs, e.g. to undo a half-made change.

### flat_record (`~/spaces/rjayroach/gems/flat_record`; 725 examples)
- **Safe with several processes:**
  - atomic writes (temp file + fsync + rename);
  - a per-model `flock`, taken while it reloads, applies the change and writes;
  - a freshness check on every read (mtime, size, inode), which covers hierarchy layouts too;
  - a Monitor per store, copies handed out instead of shared records, and the cache only changed after a successful write;
  - one-file-per-record layouts write only the changed file;
  - `StaleObjectError`, and loud errors for badly shaped files;
  - unknown YAML keys are kept.
- **ActiveRecord compatibility:** a lazy `Relation` (`default_scope` everywhere, chaining scopes, `where` with arrays and ranges plus type casting, `or`/`none`/`order` variants, calculations, `find_or_*`, `update_all`, scoped `destroy_all`/`delete_all`), validation contexts, `save(validate: false)`, `RecordNotSaved`, `new(id:)` stays a new record, `reload`, `update_column(s)`, `touch`, the `saved_change_to_*` family, `==` by id, `as_json`, string `enum`, uniqueness `scope:`/`case_sensitive:`, and `restrict_*` dependents.
- **Two fixes found through pcs:**
  - hierarchy-parent detection for multi-word and namespaced names;
  - `CollectionProxy` now delegates `pluck`/`sum`/`pick`/… to the relation instead of ActiveSupport's `Enumerable` versions.
- **`becomes(klass)`**, as in ActiveRecord: the same record as an STI sibling, unsaved, keeping its stale-check digest; attributes the new class lacks stay in the file (`spec/flat_record/becomes_spec.rb`). The existing `becomes!` (which saves immediately) is unchanged.

### pcs (`~/spaces/cnfs-io/gems/pcs`; 58 examples, rubocop clean): steps 1–5 of the build order (the milestone's code)

**Steps 1–2: skeleton**
- **Models** (`lib/pcs/models`):
  - `Site`: one per project, `Site.current`.
  - `Network`: CIDR, gateway inside the subnet, `contains?`, `netmask`, `nameservers`, `control_plane_ip`/`control_plane_interface`, `dhcp_start`/`dhcp_end` (dhcp mode only).
  - `Interface`: MAC normalised and unique, `vendor`, `configured_ip` inside its network, `reachable_ip`, `Interface.with_ip`.
  - `Host`, with single-table inheritance on `type`: `DebianHost` (`disk`, validated as `/dev/...`; `pxe?`; `requires_key?` false), `PveHost < DebianHost` ("Proxmox VE"), `PikvmHost`, `JetkvmHost`. `Host.label`/`type_choices` for the UI. `pxe_install` flag (see step 4). `site_id` defaults to the one site.
- **State machine:** `discovered → keyed → configured → provisioned`, guarded by `missing_configuration`. Debian hosts skip keying, and also need a gateway and the control plane on their network.
- **Settings** (`lib/pcs/settings.rb`): `pcm_volumes_home`; `ssh.{key_path,known_hosts}`; `scan.sudo`; `dnsmasq.{service,mode,config_dir}`; `netboot.{service,http_port,menu_timeout,menus_dir,assets_dir}`; `install.{user,password_hash,debian_codename,mirror,firmware,firmware_url,locale,keymap,packages}`.
- **Adapters** (`lib/pcs/adapters`): `SystemCmd` (argv), `Ssh` (TOFU), `Nmap` (failures say what to do: install nmap, or allow sudo / `settings.scan.sudo = false`), `Pcm`, `Download` (Net::HTTP, redirects, atomic).
- **`pcs new <site>`** creates the site, a network per local subnet, and this machine as the control plane.

**Step 3: inventory**
- **Resources** (`lib/pcs/routes`): networks, hosts, interfaces, served at `/networks` etc. and as `pcs <plural> list|show|add|update|remove`. The home page (`Views::Home`) shows the site and host counts by status. The host page shows its interfaces and what it still needs; the network page shows the hosts on it.
- **Changing a host's type** (web form or `pcs hosts update 2 --type=debian`) goes through `HostsResource#assign` → `becomes`, so the new type's fields (e.g. disk) save in the same edit.
- **`pcs networks scan [NAME] [--dry-run]`** (`Operations::Scan`): nmap ping scan per network. Matches by MAC, then by IP (discovered or configured); updates known interfaces (IP, MAC, vendor); adds new hosts as `discovered`, taking hostnames from reverse DNS when they're valid, free labels. The scan runs even in a dry run (it only reads the network).

**Step 4: reconcile and services**
- **`pcs reconcile [--dry-run]`** (`Operations::Reconcile`, split into `reconcile/files.rb` and `reconcile/installers.rb`). It writes only what changed, and removes its own files for hosts that are gone (recognised by a "Generated by pcs" header; others' files are left alone). It restarts dnsmasq (`pcm __compose restart`) only when `pcs.conf` changed and dnsmasq is running.
  - `<dnsmasq.config_dir>/pcs.conf`: proxy mode by default (`dhcp-range=<net>,proxy`, `pxe-service` lines pointing at the control plane, `port=0`); dhcp mode adds the range, router, DNS and a `dhcp-host` reservation per configured host.
  - `<netboot.menus_dir>/MAC-<hex>.ipxe` per installable host (`PxeTarget.all`: Debian-family hosts with nothing missing). The menu defaults to **boot from disk**; it defaults to **install** only when the host's `pxe_install` is set, so a stray PXE boot never wipes a machine. The install entry carries that host's own kernel parameters: a static IP/netmask/gateway/DNS via `netcfg/*` (the installed system keeps it; no rewriting of `/etc/network/interfaces`), hostname, domain, `preseed/url`.
  - `<assets_dir>/pcs/<host>.preseed.cfg`: no root login; one user (`install.user`) with NOPASSWD sudo; password `!` (locked) unless `install.password_hash` (must be `$6$…`, never plaintext); password SSH off when key-only; the **public key embedded inline** (`PublicKey.read` refuses private keys and strips the comment); `linux-image-<target arch>`; regular atomic partitioning on the host's disk; the site's timezone; a late_command that runs the post-install hook.
  - `<assets_dir>/pcs/<host>.post-install.sh`: a no-op hook, run in-target at the end of the install.
  - `<assets_dir>/debian-installer/<codename>/<arch>/{linux,initrd.gz}` for each **target** arch, fetched once. With `install.firmware`, `firmware.cpio.gz` is fetched too and `initrd-firmware.gz` is built from both (the menu then uses it). **Firmware is off by default: trixie's bundle is ~500 MB**, which the installer would hold in RAM. Point `install.firmware_url` at a trimmed cpio instead.
  - **Templates** (`lib/pcs/templates/*.erb`) can be overridden per project in `<project>/templates/<name>.erb` (`Pcs::Template`).
- **`pcs service status|start|stop|restart [dnsmasq|netboot]`** through pcm; `status` shows running or stopped, recent logs, and where pcs writes.
- **Verified for real** in a scratch site on this Mac: reconcile rendered all the files, downloaded the trixie amd64 installer from deb.debian.org, and a second run changed nothing.

**Step 4a: container definitions (drafted in `pcs/ppm/`, pcm-valid)**
- `dnsmasq` (`dockurr/dnsmasq:2.93`) and `netboot` (`netbootxyz/netbootxyz:0.7.6-nbxyz24`) compose files plus `.env.schema`s, and an `install.sh` `post_install` (volume directories; `net.ipv4.ip_unprivileged_port_start=67`; disables a system dnsmasq). **Both pass `pcm validate`.**
- **Decisions:** netboot.xyz owns TFTP; host networking for both; rootless podman with the sysctl; dnsmasq started with `--port=0` and pcs's config directory only.
- **To move them:** `pcs/ppm/README.md` lists the steps, plus the package.yml change: drop the system `dnsmasq` package.
- **Unverified until the Pi (step 7):** rootless proxy DHCP; netboot.xyz running `MAC-*.ipxe`; dnsmasq not adding `.0` to dotted boot file names.

**Step 5: install pipeline**
- **Operations** (`lib/pcs/operations`). All take `host_id:` and share `HostOperation` (SSH per host, nested Reconcile).
  - **`Key`** (PiKVM, JetKVM): with the device's password, used once and never stored, it installs pcs's public key idempotently (PiKVM wraps it in `rw`/`ro`; JetKVM keys are added by hand in its UI). Then it logs in with the key and marks the host `keyed`.
  - **`Configure`**: says exactly what's missing, or marks the host `configured` and reconciles, which writes its boot menu and preseed.
  - **`Install`** (Debian over PXE):
    1. Sets `pxe_install` and reconciles, so the menu defaults to install.
    2. Asks you to PXE boot the host.
    3. Waits for the address to go quiet, if it was up (a reinstall), then waits for the installer to answer pings.
    4. **Immediately sets the menu back to disk**, before the install reboots, so it can't loop.
    5. Forgets the old SSH host key, waits for the installed system to accept pcs's key, then marks the host `provisioned`.
    - On any failure, Ctrl-C included, and via `Install.interrupted` after a server stops mid-job, the menu goes back to disk.
- **Bug fixed along the way:** the state machine now has `action: :save`. With state_machines-activemodel, events didn't persist by default: `configure!` only changed the status in memory.
- **CLI:** `pcs hosts key ID [--password]` (prompts; nothing on the command line), `pcs hosts configure ID`, `pcs hosts install ID`, all with `--dry-run`.
- **Web:** the host page shows Key (with a password field), Configure or Install, whichever the state allows. Each starts a job and redirects to its log page; the nav bar has Jobs.
- `Adapters::Probe` (ping, TCP port); `Adapters::Ssh` gained `password:` and `forget_host_key`; `settings.install.timeout` is in minutes (default 60).
- **Verified for real** in the scratch site: the CLI and web installs (with a 3 s timeout) flipped the menu to install and back. A server killed mid-install left it set to install, and the next server start reset it.

**Specs** use `FakeSystem` (`spec/support`), which records argv and returns scripted results; `Records#control_plane` provides a cp at 10.0.0.2. `SiteSettings` gives settings rooted in the tmpdir, a key pair, a fake download and pcm; `FakeSsh` records commands and logins. `spec/pcs/web/operations_spec.rb` clicks event buttons and waits for the jobs, with pcm and downloads stubbed. `spec/pcs/web/inventory_spec.rb` drives the pages like a browser (session cookie plus CSRF token).

## Next (build order; the milestone ends at the PXE Debian install)

**Steps 3–5 are done** (see above). **The milestone's code is complete; what's left is proving it on real hardware.**

**Next: on the Pi (Linux)**
1. Move `pcs/ppm/` into pdt-ppm `packages/pcs` (see `pcs/ppm/README.md`), install the package, then `pcs service start`.
2. `pcs new <site>` on the Pi, then `pcs networks scan`, give a machine its type, disk and configured IP, then `pcs hosts configure N` and `pcs hosts install N`, and PXE boot it.
3. Watch for the three unverified assumptions in `pcs/ppm/README.md`: rootless proxy DHCP, netboot.xyz running `MAC-*.ipxe`, and dnsmasq boot file names.

**6. (After the milestone)** `UpgradeToPve`, `CreateCluster`, `JoinCluster`, `validate_networks`; then TrueNAS and storage.

**7. QEMU end-to-end test**, on Linux: a PXE Debian install from the **real, unmodified** generated files.

## Working conventions / gotchas
- **Never commit;** stage only. Always scope staging: `git add -A -- <dir>` in monorepos. Termino's generators already do this.
- **The user's uncommitted work lives in the rjayroach and cnfs-io monorepos.** Check `git status` before and after any change there.
- **Old projects need moving, not just re-scaffolding.** Scaffolds are thin and termino-owned, so re-running `termino g scaffold … --force` on an old resource prints a note about ignored old views, and switches the model to one file per record. In that case move the existing `data/<plural>.yml` into `data/<plural>/<id>.yml`.
- **Browser tests need Host and CSRF:** the Host must be a local name or IP (`HTTP_HOST=localhost` in Rack specs), and POSTs need the session cookie plus the `_csrf` token from the page's form. See `termino/spec/termino/cli/generate_scaffold_spec.rb`.
- **Puma renames its process**, so `pkill -f "<gem> server"` misses it. Find the PID with `lsof -tiTCP:<port> -sTCP:LISTEN` and send `kill -INT` (which also stops the Tailwind watcher).
- **The Tailwind watcher needs `--watch=always`;** plain `--watch` in v4 exits when stdin closes.

## Known gaps / not yet decided
- Termino: no code reloading in dev; no JS (ruby_ui's Stimulus controllers); jobs run in the server's threads, so they stop with it (cleaned up by `interrupted` hooks) and aren't shared across several server processes.
- flat_record: no transactions; `where.not` keeps nil values; `select(:a)` returns hashes; `belongs_to` isn't required by default; git auto-commit is off by default and unsafe in a server.
- pcs:
  - `Local.mac_for` reads `/sys/class/net`, so MACs are empty on macOS (fine on the Pi).
  - Powering hosts on is manual (Install asks you to PXE boot); a KVM or IPMI power hook would come later.
  - Configure doesn't push network config to KVMs yet.
  - The web's Key password crosses the LAN over plain HTTP to the pcs server.
  - Proxmox, TrueNAS and clustering are step 6.
