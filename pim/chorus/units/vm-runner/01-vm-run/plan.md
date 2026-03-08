---
---

# Plan 01 — VM Run Command

## Context

Read before starting:
- `docs/vm-runner/README.md` — tier overview
- `lib/pim/cli.rb` — CLI registry (add new vm commands here)
- `lib/pim/services/qemu_command_builder.rb` — QEMU command assembly
- `lib/pim/services/qemu_vm.rb` — VM process management
- `lib/pim/services/qemu_disk_image.rb` — disk image operations (check for overlay/clone support)
- `lib/pim/services/qemu.rb` — QEMU utilities (port finding, EFI firmware paths)
- `lib/pim/services/registry.rb` — image registry (find built images)
- `lib/pim/models/build.rb` — build recipe model (memory, cpus, ssh_user, arch)
- `lib/pim/commands/builds_command.rb` — `Verify#boot_interactive` method (existing interactive boot logic to extract from)

## Goal

Create `pim vm run <build_id>` — boot a VM from a previously built image with support for snapshot mode (default), CoW overlay (`--no-snapshot`), and full clone (`--clone`). User-mode networking only in this plan. Bridged networking is plan-02.

## Implementation

### Step 1: Create `Pim::VmRunner` service

**File:** `lib/pim/services/vm_runner.rb`

This service orchestrates the full boot sequence. Extract and generalize the logic currently in `BuildsCommand::Verify#boot_interactive`.

```ruby
# frozen_string_literal: true

module Pim
  class VmRunner
    class Error < StandardError; end

    attr_reader :vm, :ssh_port, :image_path

    def initialize(build:, name: nil)
      @build = build
      @profile = build.resolved_profile
      @arch = build.arch
      @name = name || build.id
      @vm = nil
      @ssh_port = nil
      @image_path = nil
      @temp_efi_vars = nil
    end

    # Boot the VM.
    #
    # Options:
    #   snapshot:  true (default) — QEMU -snapshot, no disk changes
    #   clone:     false — if true, qemu-img convert full copy
    #   console:   false — if true, attach serial to terminal (foreground)
    #   memory:    override from build recipe
    #   cpus:      override from build recipe
    #
    # When snapshot: false and clone: false, creates a CoW overlay.
    # When clone: true, creates a full independent copy.
    # When snapshot: true (default), boots read-only with -snapshot.
    #
    # Returns self. Access @vm, @ssh_port, @image_path after boot.
    def run(snapshot: true, clone: false, console: false, memory: nil, cpus: nil)
      golden_image = find_golden_image
      @image_path = prepare_image(golden_image, snapshot: snapshot, clone: clone)

      @ssh_port = Pim::Qemu.find_available_port
      builder = build_qemu_command(
        memory: memory || @build.memory,
        cpus: cpus || @build.cpus,
        snapshot: snapshot
      )

      @vm = Pim::QemuVM.new(command: builder.build, ssh_port: @ssh_port)

      if console
        print_connection_info
        @vm.start_console(detach: false)
        @vm.wait_for_exit
      else
        @vm.start_background
        print_connection_info
      end

      self
    end

    def stop
      @vm&.shutdown(timeout: 30)
      cleanup_efi_vars
    end

    def kill
      @vm&.kill
      cleanup_efi_vars
    end

    def running?
      @vm&.running? || false
    end

    private

    def find_golden_image
      registry = Pim::Registry.new(image_dir: Pim.config.image_dir)
      entry = registry.find(profile: @profile.id, arch: @arch)

      unless entry
        raise Error, "No image found for #{@profile.id}-#{@arch}. Run 'pim build run #{@build.id}' first."
      end

      path = entry['path']
      unless File.exist?(path)
        raise Error, "Image file missing: #{path}"
      end

      path
    end

    def prepare_image(golden_image, snapshot:, clone:)
      # Snapshot mode: use golden image directly (QEMU -snapshot protects it)
      return golden_image if snapshot

      vm_dir = File.join(Pim.data_home, 'vms')
      FileUtils.mkdir_p(vm_dir)
      timestamp = Time.now.strftime('%Y%m%d-%H%M%S')

      if clone
        # Full independent copy
        dest = File.join(vm_dir, "#{@name}-#{timestamp}.qcow2")
        puts "Cloning image (this may take a moment)..."
        Pim::QemuDiskImage.convert(golden_image, dest, format: 'qcow2')
        dest
      else
        # CoW overlay — fast, space-efficient
        dest = File.join(vm_dir, "#{@name}-#{timestamp}.qcow2")
        Pim::QemuDiskImage.create_overlay(golden_image, dest)
        dest
      end
    end

    def build_qemu_command(memory:, cpus:, snapshot:)
      builder = Pim::QemuCommandBuilder.new(
        arch: @arch,
        memory: memory,
        cpus: cpus,
        display: false,
        serial: nil
      )

      builder.add_drive(@image_path, format: 'qcow2')
      builder.add_user_net(host_port: @ssh_port, guest_port: 22)
      builder.extra_args('-snapshot') if snapshot

      setup_efi(builder) if @arch == 'arm64'

      builder
    end

    def setup_efi(builder)
      efi_code = Pim::Qemu.find_efi_firmware
      # EFI vars file lives alongside the golden image
      golden_image = find_golden_image
      efi_vars = golden_image.sub(/\.qcow2$/, '-efivars.fd')

      return unless efi_code && File.exist?(efi_vars)

      # Copy vars to temp file — -snapshot doesn't apply to pflash drives
      @temp_efi_vars = "#{@image_path}-efivars.fd"
      FileUtils.cp(efi_vars, @temp_efi_vars)

      builder.extra_args(
        '-drive', "if=pflash,format=raw,file=#{efi_code},readonly=on",
        '-drive', "if=pflash,format=raw,file=#{@temp_efi_vars}"
      )
    end

    def print_connection_info
      puts "VM: #{@name}"
      puts "  PID:     #{@vm.pid}"
      puts "  Arch:    #{@arch}"
      puts "  Image:   #{@image_path}"
      puts "  SSH:     ssh -p #{@ssh_port} #{@build.ssh_user}@localhost"
      puts "  Network: user (port forwarding)"
    end

    def cleanup_efi_vars
      FileUtils.rm_f(@temp_efi_vars) if @temp_efi_vars
    end
  end
end
```

**Notes for implementer:**
- Check `QemuDiskImage` for existing `convert` and `create_overlay` methods. If they don't exist, add them:
  - `QemuDiskImage.create_overlay(backing_file, dest)` → `qemu-img create -f qcow2 -b <backing> -F qcow2 <dest>`
  - `QemuDiskImage.convert(source, dest, format:)` → `qemu-img convert -O qcow2 <source> <dest>`
- `Pim.data_home` should resolve to `~/.local/share/pim`. Check if this constant exists; if not, add it alongside the existing XDG constants in `lib/pim.rb`.
- The `setup_efi` method calls `find_golden_image` a second time — refactor to cache the golden path as an instance variable set in `run` before `prepare_image`.

### Step 2: Create `VmCommand` and `Vm::Run` command

**File:** `lib/pim/commands/vm_command.rb`

```ruby
# frozen_string_literal: true

module Pim
  class VmCommand < RestCli::Command
    class Run < self
      desc "Boot a VM from a built image"

      argument :build_id, required: true, desc: "Build recipe ID (e.g., default-arm64)"

      option :console, type: :boolean, default: false, aliases: ["-c"],
             desc: "Attach serial console (foreground, Ctrl+A X to quit)"
      option :snapshot, type: :boolean, default: true,
             desc: "Boot read-only, discard changes on exit (default)"
      option :clone, type: :boolean, default: false,
             desc: "Create a full independent copy of the image"
      option :name, type: :string, default: nil,
             desc: "Name for this VM instance (default: build_id)"
      option :memory, type: :integer, default: nil,
             desc: "Override memory in MB"
      option :cpus, type: :integer, default: nil,
             desc: "Override CPU count"

      def call(build_id:, console: false, snapshot: true, clone: false, name: nil, memory: nil, cpus: nil, **)
        require_relative "../services/vm_runner"

        build = Pim::Build.find(build_id)

        # --clone implies --no-snapshot
        snapshot = false if clone

        runner = Pim::VmRunner.new(build: build, name: name || build_id)
        runner.run(
          snapshot: snapshot,
          clone: clone,
          console: console,
          memory: memory,
          cpus: cpus
        )

        # If not console mode, VM is backgrounded — inform user how to stop it
        unless console
          puts
          puts "VM is running in the background."
          puts "Stop with: pim vm stop  (or kill PID #{runner.vm.pid})"
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Build '#{build_id}' not found")
      rescue Pim::VmRunner::Error => e
        Pim.exit!(1, message: e.message)
      end
    end
  end
end
```

### Step 3: Register in CLI

**File:** `lib/pim/cli.rb`

Add require at top:
```ruby
require_relative "commands/vm_command"
```

Add inside the `inside_project` block:
```ruby
# VMs
register "vm run",          VmCommand::Run
```

### Step 4: Add `QemuDiskImage` overlay and convert methods (if missing)

Check `lib/pim/services/qemu_disk_image.rb`. If these class methods don't exist, add:

```ruby
# Create a CoW overlay backed by an existing image
def self.create_overlay(backing_file, dest)
  run_command('qemu-img', 'create', '-f', 'qcow2',
              '-b', backing_file, '-F', 'qcow2', dest)
end

# Full copy/convert to a new image
def self.convert(source, dest, format: 'qcow2')
  run_command('qemu-img', 'convert', '-O', format, source, dest)
end

private_class_method def self.run_command(*cmd)
  output, status = Open3.capture2e(*cmd)
  unless status.success?
    raise Error, "#{cmd.first} failed: #{output}"
  end
  output
end
```

### Step 5: Verify `Pim.data_home` exists

Check `lib/pim.rb` for XDG path constants. There should be something like:
```ruby
def self.data_home
  File.join(ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')), 'pim')
end
```

If it doesn't exist, add it. The `vms/` subdirectory under data_home is where overlays and clones live.

### Step 6: Simplify `BuildsCommand::Verify#boot_interactive`

Now that `VmRunner` exists, the `boot_interactive` method in `BuildsCommand::Verify` can delegate to it:

```ruby
def boot_interactive(build)
  require_relative "../services/vm_runner"

  runner = Pim::VmRunner.new(build: build)
  runner.run(snapshot: true, console: true)
end
```

This removes ~50 lines of duplicated QEMU boot logic from the builds command.

## Test Spec

### Unit tests

**File:** `spec/services/vm_runner_spec.rb`

- `VmRunner.new(build:)` accepts a build and extracts profile, arch, name
- `#prepare_image` with `snapshot: true` returns the golden image path unchanged
- `#prepare_image` with `snapshot: false` calls `QemuDiskImage.create_overlay`
- `#prepare_image` with `clone: true` calls `QemuDiskImage.convert`
- EFI vars are copied for arm64 builds

**File:** `spec/services/qemu_disk_image_spec.rb` (extend existing)

- `.create_overlay` calls `qemu-img create` with correct backing file args
- `.convert` calls `qemu-img convert` with correct format

**File:** `spec/commands/vm_command_spec.rb`

- `VmCommand::Run` is registered at `vm run`
- `--clone` implies `snapshot: false`
- Missing build_id produces error

### Manual verification

```bash
# Snapshot mode (default) — boots, changes discarded on exit
pim vm run default-arm64 --console

# Background mode — boots, prints connection info, returns to shell
pim vm run default-arm64

# CoW overlay — creates overlay, changes persist in overlay file
pim vm run default-arm64 --no-snapshot --console

# Full clone — slow, independent copy
pim vm run default-arm64 --clone --console

# Overrides
pim vm run default-arm64 --memory 4096 --cpus 4
```

## Verification

- [ ] `pim vm run default-arm64 --console` boots and attaches serial (Ctrl+A X to quit)
- [ ] `pim vm run default-arm64` boots in background, prints SSH command
- [ ] `pim vm run default-arm64 --no-snapshot` creates overlay in `~/.local/share/pim/vms/`
- [ ] `pim vm run default-arm64 --clone` creates full copy in `~/.local/share/pim/vms/`
- [ ] `pim vm run nonexistent` prints friendly error
- [ ] `pim build verify <id> --console` still works (now delegates to VmRunner)
- [ ] `bundle exec rspec` passes (existing + new specs)
- [ ] EFI vars handled for arm64 in all three modes (snapshot, overlay, clone)
