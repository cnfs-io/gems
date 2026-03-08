---
---

# Plan 01 — Collection Layout and Defaults

## Context

Read before starting:
- `lib/pim/models/profile.rb`
- `lib/pim/models/iso.rb`
- `lib/pim/models/build.rb`
- `lib/pim/models/target.rb`
- `lib/pim/new/scaffold.rb`
- `lib/pim/new/template/` (entire directory tree)
- `docs/collection-layout/README.md`

## Implementation Spec

### 1. Remove `file_layout :individual` from all models

Edit these four files and remove the `file_layout :individual` line:
- `lib/pim/models/profile.rb`
- `lib/pim/models/iso.rb`
- `lib/pim/models/build.rb`
- `lib/pim/models/target.rb`

FlatRecord defaults to `:collection`, so no replacement line is needed.

### 2. Remove `# read_only true` from all models

Same four files. Delete the commented-out `# read_only true` line from each.

### 3. Update scaffold — remove data subdirectories

In `lib/pim/new/scaffold.rb`, update `SCAFFOLD_DIRS`:

**Before:**
```ruby
SCAFFOLD_DIRS = %w[
  data/builds data/isos data/profiles data/targets
  resources/post_installs resources/preseeds resources/scripts resources/verifications
].freeze
```

**After:**
```ruby
SCAFFOLD_DIRS = %w[
  data
  resources/post_installs resources/preseeds resources/scripts resources/verifications
].freeze
```

### 4. Replace template data directory structure

Delete the entire `lib/pim/new/template/data/` directory tree (subdirectories and files).

Create these four files:

#### `lib/pim/new/template/data/profiles.yml`

```yaml
---
- id: default
  hostname: debian
  username: ansible
  password: changeme
  fullname: Ansible User
  locale: en_US.UTF-8
  keyboard: us
  domain: local
  mirror_host: deb.debian.org
  mirror_path: /debian
  http_proxy: ""
  timezone: UTC
  partitioning_method: regular
  partitioning_recipe: atomic
  tasksel: "standard, ssh-server"
  packages: openssh-server curl sudo qemu-guest-agent
  grub_device: default
```

#### `lib/pim/new/template/data/targets.yml`

```yaml
---
- id: local
  type: local
```

#### `lib/pim/new/template/data/isos.yml`

```yaml
---
- id: debian-13-amd64
  name: Debian 13.3.0 amd64 netinst
  url: https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.3.0-amd64-netinst.iso
  checksum_url: https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS
  filename: debian-13.3.0-amd64-netinst.iso
  architecture: amd64

- id: debian-13-arm64
  name: Debian 13.3.0 arm64 netinst
  url: https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/debian-13.3.0-arm64-netinst.iso
  checksum_url: https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/SHA256SUMS
  filename: debian-13.3.0-arm64-netinst.iso
  architecture: arm64
```

#### `lib/pim/new/template/data/builds.yml`

```yaml
---
- id: default
  profile: default
  iso: debian-13-amd64
  target: local
  distro: debian
```

### 5. Update scaffold output message

In `scaffold.rb`, the `create` method currently prints each `SCAFFOLD_DIRS` entry. Update the output to also list the template data files so the user sees what was created. The existing `copy_templates` method already handles copying files from the template directory — this should work without changes since the `.yml` files are now directly under `data/`.

### 6. Update specs

Any specs that reference the old individual layout paths or scaffold structure need updating:
- Scaffold specs should verify the new file structure (`.yml` files in `data/`, no subdirectories)
- Model specs that create test fixtures may need to switch from individual files to collection files
- Search for `data/profiles/` , `data/builds/`, `data/isos/`, `data/targets/` in spec files and update

## Test Spec

### Scaffold spec (`spec/pim/new/scaffold_spec.rb` or similar)

1. **test: scaffold creates collection data files** — After `Scaffold.new(tmpdir).create`, verify:
   - `tmpdir/data/profiles.yml` exists and contains a YAML array with one record (id: default)
   - `tmpdir/data/targets.yml` exists and contains a YAML array with one record (id: local)
   - `tmpdir/data/isos.yml` exists and contains a YAML array with two records (debian-13-amd64, debian-13-arm64)
   - `tmpdir/data/builds.yml` exists and contains a YAML array with one record (id: default)
   - No `data/profiles/`, `data/builds/`, `data/isos/`, or `data/targets/` subdirectories exist

### Model integration spec

2. **test: models load from collection files** — Boot PIM against a scaffolded tmpdir project, verify:
   - `Pim::Profile.all.count == 1`
   - `Pim::Iso.all.count == 2`
   - `Pim::Build.all.count == 1`
   - `Pim::Target.all.count == 1`
   - `Pim::Build.find("default").resolved_profile.id == "default"`
   - `Pim::Build.find("default").resolved_iso.id == "debian-13-amd64"`

## Verification

```bash
bundle exec rspec
```

All green. Additionally, manual smoke test:

```bash
cd /tmp && pim new testproject && cd testproject
pim iso list       # shows debian-13-amd64, debian-13-arm64
pim build list     # shows default
pim profile list   # shows default
pim target list    # shows local
```
