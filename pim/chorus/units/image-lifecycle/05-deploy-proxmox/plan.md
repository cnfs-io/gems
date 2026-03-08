---
---

# Plan 05 — Deploy to Proxmox

## Context

Read before starting:
- `docs/image-lifecycle/README.md` — tier overview
- `docs/image-lifecycle/plan-04-image-publish.md` — plan 04 (must be complete)
- `lib/pim/models/target.rb` — Target base class with `deploy(image_path)` stub
- `lib/pim/models/targets/proxmox.rb` — ProxmoxTarget with attributes (host, node, storage, etc.)
- `lib/pim/services/registry.rb` — Registry v2 (record_deployment)
- `lib/pim/services/ssh_connection.rb` — SSH wrapper (for SCP upload)
- `lib/pim/config.rb` — ImageSettings (auto_publish)

Reference (do NOT modify):
- Proxmox VE API documentation: https://pve.proxmox.com/pve-docs/api-viewer/
- PCS project for how Proxmox clusters are managed

## Goal

Implement `pim image deploy <image_id> <target_id>` for Proxmox targets. This uploads a published qcow2 to a Proxmox node, imports it as a disk, and creates a VM template that can be cloned by PCS or Proxmox UI.

## Background

### Proxmox template workflow

To create a VM template on Proxmox from a qcow2 image:

1. SCP the qcow2 to the Proxmox node (temp location like `/tmp/`)
2. Create a VM shell: `qm create <vmid> --name <name> --memory <mem> --cores <cores> --net0 virtio,bridge=<bridge>`
3. Import the disk: `qm importdisk <vmid> /tmp/image.qcow2 <storage>`
4. Attach the disk: `qm set <vmid> --scsi0 <storage>:<vmid>/vm-<vmid>-disk-0.raw`
5. Set boot order: `qm set <vmid> --boot order=scsi0`
6. Add cloud-init drive (optional): `qm set <vmid> --ide2 <storage>:cloudinit`
7. Convert to template: `qm template <vmid>`
8. Clean up temp file

Alternatively, Proxmox's REST API can do most of this, but the `qm` CLI approach is simpler and doesn't require API token setup for the initial implementation. The target's `host` + SSH is sufficient.

### Target data file example

```yaml
# data/targets/proxmox-sg.yml
id: proxmox-sg
type: proxmox
name: Singapore Proxmox Cluster
host: pve1.rj-sg.local
node: pve1
storage: local-lvm
vm_id_start: 9000
bridge: vmbr0
```

## Implementation

### Step 1: Create `Pim::ProxmoxDeployer` service

**File:** `lib/pim/services/deployers/proxmox_deployer.rb`

```ruby
# frozen_string_literal: true

module Pim
  class ProxmoxDeployer
    class Error < StandardError; end

    DEFAULT_MEMORY = 2048
    DEFAULT_CORES = 2

    def initialize(target:, image:, build: nil)
      @target = target
      @image = image
      @build = build
      @ssh = nil
    end

    # Deploy image to Proxmox as a VM template
    #
    # Options:
    #   vm_id:    specific VM ID (default: auto from target.vm_id_start)
    #   name:     template name (default: image label or id)
    #   memory:   MB (default: from build or 2048)
    #   cores:    CPU cores (default: from build or 2)
    #   dry_run:  show what would be done without doing it
    def deploy(vm_id: nil, name: nil, memory: nil, cores: nil, dry_run: false)
      validate!

      vm_id ||= next_vm_id
      name ||= template_name
      memory ||= @build&.memory || DEFAULT_MEMORY
      cores ||= @build&.cpus || DEFAULT_CORES
      storage = @target.storage || 'local-lvm'
      bridge = @target.bridge || 'vmbr0'
      node = @target.node

      remote_path = "/tmp/pim-deploy-#{@image.id}.qcow2"

      steps = [
        "Upload #{@image.filename} to #{@target.host}:#{remote_path}",
        "qm create #{vm_id} --name #{name} --memory #{memory} --cores #{cores} --net0 virtio,bridge=#{bridge}",
        "qm importdisk #{vm_id} #{remote_path} #{storage}",
        "qm set #{vm_id} --scsi0 #{storage}:vm-#{vm_id}-disk-0 --scsihw virtio-scsi-pci",
        "qm set #{vm_id} --boot order=scsi0",
        "qm set #{vm_id} --serial0 socket --vga serial0",
        "qm template #{vm_id}",
        "rm #{remote_path}"
      ]

      if dry_run
        puts "Dry run — would execute:"
        steps.each_with_index { |s, i| puts "  #{i + 1}. #{s}" }
        return { vm_id: vm_id, name: name, dry_run: true }
      end

      connect_ssh!

      # 1. Upload
      puts "Uploading #{@image.filename} to #{@target.host}..."
      upload_image(remote_path)

      # 2. Create VM
      puts "Creating VM #{vm_id} (#{name})..."
      ssh_exec("qm create #{vm_id} --name #{name} --memory #{memory} --cores #{cores} " \
               "--net0 virtio,bridge=#{bridge}")

      # 3. Import disk
      puts "Importing disk to #{storage}..."
      output = ssh_exec("qm importdisk #{vm_id} #{remote_path} #{storage}")
      # Parse the disk name from import output
      disk_ref = parse_disk_ref(output, vm_id, storage)

      # 4. Attach disk
      puts "Attaching disk..."
      ssh_exec("qm set #{vm_id} --scsi0 #{disk_ref} --scsihw virtio-scsi-pci")

      # 5. Boot order
      ssh_exec("qm set #{vm_id} --boot order=scsi0")

      # 6. Serial console (for headless access)
      ssh_exec("qm set #{vm_id} --serial0 socket --vga serial0")

      # 7. Convert to template
      puts "Converting to template..."
      ssh_exec("qm template #{vm_id}")

      # 8. Cleanup
      ssh_exec("rm -f #{remote_path}")

      puts "Deployed as template #{vm_id} (#{name}) on #{@target.host}"

      { vm_id: vm_id, name: name, node: node, storage: storage }
    end

    private

    def validate!
      raise Error, "Image file missing: #{@image.path}" unless @image.exists?

      unless @image.published? || @image.golden?
        raise Error, "Image '#{@image.id}' must be published before deploying to Proxmox.\n" \
                     "Run: pim image publish #{@image.id}"
      end

      raise Error, "Target host not configured" unless @target.host
      raise Error, "Target node not configured" unless @target.node
    end

    def connect_ssh!
      @ssh = Pim::SSHConnection.new(
        host: @target.host,
        port: 22,
        user: 'root',  # Proxmox uses root for qm commands
        key_file: ssh_key_path
      )
    end

    def ssh_key_path
      # Use default SSH key, or target-specific key if configured
      key = @target.respond_to?(:ssh_key) ? @target.ssh_key : nil
      key || File.expand_path('~/.ssh/id_rsa')
    end

    def upload_image(remote_path)
      @ssh.upload(@image.path, remote_path)
    end

    def ssh_exec(command)
      result = @ssh.execute(command, sudo: false)
      unless result[:exit_code] == 0
        stderr = result[:stderr].strip
        raise Error, "Command failed: #{command}\n#{stderr}"
      end
      result[:stdout]
    end

    def next_vm_id
      start = @target.vm_id_start || 9000
      # Query existing VMs to find next available ID
      begin
        result = @ssh.execute("qm list 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n | tail -1")
        max_existing = result[:stdout].strip.to_i
        [start, max_existing + 1].max
      rescue StandardError
        start
      end
    end

    def template_name
      label = @image.label
      if label
        "pim-#{@image.profile}-#{label}"
      else
        "pim-#{@image.id}"
      end
    end

    def parse_disk_ref(output, vm_id, storage)
      # qm importdisk output includes a line like:
      # "Successfully imported disk as 'local-lvm:vm-9000-disk-0'"
      if output =~ /imported disk as '([^']+)'/
        $1
      else
        # Fallback: construct expected path
        "#{storage}:vm-#{vm_id}-disk-0"
      end
    end
  end
end
```

### Step 2: Implement `ProxmoxTarget#deploy`

**File:** `lib/pim/models/targets/proxmox.rb`

```ruby
class ProxmoxTarget < Target
  sti_type "proxmox"

  attribute :host, :string
  attribute :node, :string
  attribute :storage, :string
  attribute :api_token_id, :string
  attribute :api_token_secret, :string
  attribute :vm_id_start, :integer
  attribute :bridge, :string
  attribute :ssh_key, :string

  def deploy(image, build: nil, **options)
    require_relative "../../services/deployers/proxmox_deployer"
    deployer = Pim::ProxmoxDeployer.new(target: self, image: image, build: build)
    deployer.deploy(**options)
  end
end
```

### Step 3: Create `ImageCommand::Deploy`

**File:** `lib/pim/commands/image_command.rb` (add class)

```ruby
class Deploy < self
  desc "Deploy an image to a target"

  argument :image_id, required: true, desc: "Image ID"
  argument :target_id, required: true, desc: "Target ID (from 'pim target list')"

  option :vm_id, type: :integer, default: nil,
         desc: "Specific VM ID (Proxmox only, default: auto)"
  option :name, type: :string, default: nil,
         desc: "Template/instance name (default: auto from image)"
  option :memory, type: :integer, default: nil,
         desc: "Memory in MB (default: from build recipe)"
  option :cpus, type: :integer, default: nil,
         desc: "CPU cores (default: from build recipe)"
  option :dry_run, type: :boolean, default: false, aliases: ["-n"],
         desc: "Show what would be done without doing it"

  def call(image_id:, target_id:, vm_id: nil, name: nil, memory: nil, cpus: nil, dry_run: false, **)
    registry = Pim::Registry.new
    image = registry.find(image_id)

    unless image
      Pim.exit!(1, message: "Image '#{image_id}' not found. Run 'pim image list'.")
      return
    end

    target = Pim::Target.find(target_id)

    # Auto-publish if configured
    if image.overlay? && !image.published?
      if Pim.config.images.auto_publish
        puts "Auto-publishing overlay before deploy..."
        publish_image(registry, image_id)
        image = registry.find(image_id)  # re-read after publish
      else
        Pim.exit!(1, message: "Image '#{image_id}' is an overlay and must be published first.\n" \
                              "Run: pim image publish #{image_id}\n" \
                              "Or set config.images.auto_publish = true in pim.rb")
        return
      end
    end

    # Resolve build recipe for defaults (memory, cpus)
    build = resolve_build(image)

    puts "Deploying '#{image_id}' to '#{target_id}' (#{target.class.name.split('::').last})..."
    result = target.deploy(image, build: build,
                           vm_id: vm_id, name: name,
                           memory: memory, cpus: cpus,
                           dry_run: dry_run)

    # Record deployment in registry (unless dry run)
    unless dry_run
      registry.record_deployment(
        image_id,
        target: target_id,
        target_type: target.type,
        metadata: result.slice(:vm_id, :name, :node).transform_keys(&:to_s)
      )
    end
  rescue FlatRecord::RecordNotFound
    Pim.exit!(1, message: "Target '#{target_id}' not found. Run 'pim target list'.")
  rescue Pim::ProxmoxDeployer::Error => e
    Pim.exit!(1, message: e.message)
  end

  private

  def resolve_build(image)
    # Try to find the build recipe that produced this image
    build_id = "#{image.profile}-#{image.arch}"
    Pim::Build.find(build_id)
  rescue FlatRecord::RecordNotFound
    # Fall back to just the profile name
    Pim::Build.find(image.profile) rescue nil
  end

  def publish_image(registry, image_id)
    image = registry.find!(image_id)
    disk = Pim::QemuDiskImage.new(image.path)
    temp = "#{image.path}.publish-tmp"
    disk.convert(temp, format: 'qcow2')
    FileUtils.mv(temp, image.path)
    registry.update_status(image_id, 'published')
  end
end
```

### Step 4: Register deploy command in CLI

**File:** `lib/pim/cli.rb`

```ruby
register "image deploy",    ImageCommand::Deploy
```

### Step 5: Create deployers directory and require

**File:** `lib/pim.rb`

Add directory: `lib/pim/services/deployers/`

The deployer is lazy-loaded (required inside `ProxmoxTarget#deploy`), so no top-level require needed. But create the directory.

### Step 6: Add `ssh_key` attribute to ProxmoxTarget

Already shown in step 2. This allows per-target SSH key configuration:

```yaml
# data/targets/proxmox-sg.yml
id: proxmox-sg
type: proxmox
host: pve1.rj-sg.local
node: pve1
storage: local-lvm
vm_id_start: 9000
bridge: vmbr0
ssh_key: ~/.ssh/pve_deploy
```

## Test Spec

### Unit tests

**File:** `spec/services/deployers/proxmox_deployer_spec.rb`

- `#validate!` raises for missing image file
- `#validate!` raises for unpublished overlay
- `#validate!` allows golden images (standalone)
- `#template_name` uses label when present, falls back to image id
- `#parse_disk_ref` extracts disk path from qm output
- `#deploy(dry_run: true)` prints steps without executing

**File:** `spec/commands/image_command_spec.rb` (extend)

- `Deploy` registered at `image deploy`
- Missing image prints error
- Missing target prints error
- `--dry-run` flag prevents execution
- Auto-publish triggered when `auto_publish` is true

### Manual verification

```bash
# Prerequisite: published image and Proxmox target configured
pim image publish default-arm64

# Dry run first
pim image deploy default-arm64 proxmox-sg --dry-run
# Should print numbered steps without executing

# Actual deploy
pim image deploy default-arm64 proxmox-sg
# Should: upload, create VM, import disk, template, cleanup

# Check deployment was recorded
pim image show default-arm64
# Should show deployment entry with target and timestamp

# Deploy provisioned image
pim image deploy default-arm64-k8s-node proxmox-sg --vm-id 9010
```

## Verification

- [ ] `pim image deploy <image> <target> --dry-run` shows steps without executing
- [ ] `pim image deploy <image> <target>` uploads to Proxmox and creates template
- [ ] Deploying an unpublished overlay errors with helpful message
- [ ] Auto-publish works when `config.images.auto_publish = true`
- [ ] VM ID auto-increments from target's `vm_id_start`
- [ ] `--vm-id` overrides auto VM ID
- [ ] `--name` overrides auto template name
- [ ] Deployment recorded in image registry
- [ ] `pim image show <id>` displays deployment history
- [ ] SSH key from target config is used
- [ ] `bundle exec rspec` passes
