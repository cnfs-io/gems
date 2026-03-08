---
---

# Plan 03 — VM Lifecycle (list, stop, ssh)

## Context

Read before starting:
- `docs/vm-runner/README.md` — tier overview
- `docs/vm-runner/plan-01-vm-run.md` — plan 01 (must be complete)
- `docs/vm-runner/plan-02-bridged-networking.md` — plan 02 (must be complete)
- `lib/pim/services/vm_runner.rb` — current runner (needs to write state on boot)
- `lib/pim/commands/vm_command.rb` — add List, Stop, Ssh commands

## Goal

Track running VMs with lightweight state files so `pim vm list`, `pim vm stop`, and `pim vm ssh` work. VMs are identified by a numeric index from the list (like `docker ps` numbering).

## Implementation

### Step 1: Create `Pim::VmRegistry` service

**File:** `lib/pim/services/vm_registry.rb`

Manages state files in the runtime directory. Each running VM gets a YAML state file.

```ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Pim
  class VmRegistry
    STATE_DIR_NAME = 'vms'

    def initialize
      @state_dir = File.join(runtime_dir, STATE_DIR_NAME)
      FileUtils.mkdir_p(@state_dir)
    end

    # Register a running VM, returns the assigned instance name
    def register(name:, pid:, build_id:, image_path:, ssh_port: nil,
                 network: 'user', mac: nil, snapshot: true)
      # Ensure unique name — append counter if needed
      actual_name = unique_name(name)

      state = {
        'name' => actual_name,
        'pid' => pid,
        'build_id' => build_id,
        'image_path' => image_path,
        'ssh_port' => ssh_port,
        'network' => network,
        'mac' => mac,
        'bridge_ip' => nil,
        'snapshot' => snapshot,
        'started_at' => Time.now.utc.iso8601
      }

      File.write(state_file(actual_name), YAML.dump(state))
      actual_name
    end

    # Update a field (e.g., bridge_ip after discovery)
    def update(name, **fields)
      path = state_file(name)
      return unless File.exist?(path)

      state = YAML.load_file(path)
      fields.each { |k, v| state[k.to_s] = v }
      File.write(path, YAML.dump(state))
    end

    # List all registered VMs, pruning dead ones
    def list
      entries = []
      Dir.glob(File.join(@state_dir, '*.yml')).each do |path|
        state = YAML.load_file(path)
        next unless state.is_a?(Hash)

        pid = state['pid']
        if pid && process_alive?(pid)
          entries << state
        else
          # Dead VM — clean up state file
          File.delete(path)
        end
      end

      entries.sort_by { |e| e['started_at'] || '' }
    end

    # Find a VM by name or numeric index (1-based)
    def find(identifier)
      all = list
      return nil if all.empty?

      # Try numeric index first (1-based)
      if identifier.match?(/\A\d+\z/)
        idx = identifier.to_i - 1
        return all[idx] if idx >= 0 && idx < all.size
      end

      # Try name match
      all.find { |e| e['name'] == identifier }
    end

    # Unregister a VM (remove state file)
    def unregister(name)
      path = state_file(name)
      File.delete(path) if File.exist?(path)
    end

    private

    def runtime_dir
      Pim::Qemu.runtime_dir
    end

    def state_file(name)
      File.join(@state_dir, "#{name}.yml")
    end

    def unique_name(base)
      return base unless File.exist?(state_file(base))

      counter = 2
      loop do
        candidate = "#{base}-#{counter}"
        return candidate unless File.exist?(state_file(candidate))
        counter += 1
      end
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true  # exists but different user (sudo/root)
    end
  end
end
```

### Step 2: Update `VmRunner` to register/unregister VMs

After starting the VM, register it:

```ruby
def run(...)
  # ... existing boot logic ...

  # Register with VM registry
  @registry = Pim::VmRegistry.new
  @instance_name = @registry.register(
    name: @name,
    pid: @vm.pid,
    build_id: @build.id,
    image_path: @image_path,
    ssh_port: @ssh_port,
    network: @bridged ? 'bridged' : 'user',
    mac: @mac,
    snapshot: snapshot
  )

  # For bridged mode, try to discover and update IP
  if @bridged
    ip = discover_ip(timeout: 30)
    @registry.update(@instance_name, bridge_ip: ip) if ip
  end

  # ... print connection info ...
end

def stop
  @vm&.shutdown(timeout: 30)
  @registry&.unregister(@instance_name) if @instance_name
  cleanup_efi_vars
end
```

### Step 3: Add `VmCommand::List`

```ruby
class List < self
  desc "List running VMs"

  def call(**)
    require_relative "../services/vm_registry"

    registry = Pim::VmRegistry.new
    vms = registry.list

    if vms.empty?
      puts "No running VMs."
      return
    end

    # Header
    puts format("%-4s %-25s %-8s %-10s %-30s",
                "#", "NAME", "PID", "NETWORK", "SSH")
    puts "-" * 80

    vms.each_with_index do |vm, idx|
      ssh_info = case vm['network']
                 when 'bridged'
                   ip = vm['bridge_ip']
                   ip ? "ssh #{ssh_user(vm)}@#{ip}" : "MAC: #{vm['mac']}"
                 else
                   "ssh -p #{vm['ssh_port']} #{ssh_user(vm)}@localhost"
                 end

      puts format("%-4s %-25s %-8s %-10s %-30s",
                  idx + 1, vm['name'], vm['pid'], vm['network'], ssh_info)
    end
  end

  private

  def ssh_user(vm)
    build = Pim::Build.find(vm['build_id'])
    build.ssh_user
  rescue FlatRecord::RecordNotFound
    "ansible"
  end
end
```

### Step 4: Add `VmCommand::Stop`

```ruby
class Stop < self
  desc "Stop a running VM"

  argument :identifier, required: true, desc: "VM number (from 'vm list') or name"

  option :force, type: :boolean, default: false, aliases: ["-f"],
         desc: "Force kill instead of graceful shutdown"

  def call(identifier:, force: false, **)
    require_relative "../services/vm_registry"

    registry = Pim::VmRegistry.new
    vm = registry.find(identifier)

    unless vm
      Pim.exit!(1, message: "VM '#{identifier}' not found. Run 'pim vm list' to see running VMs.")
    end

    pid = vm['pid']
    name = vm['name']

    begin
      if force
        # sudo kill for bridged VMs (root-owned process on macOS)
        if vm['network'] == 'bridged' && macos?
          system('sudo', 'kill', '-9', pid.to_s)
        else
          Process.kill('KILL', pid)
        end
        puts "Killed VM '#{name}' (PID #{pid})"
      else
        # Graceful shutdown via SSH if possible
        if try_ssh_shutdown(vm)
          puts "Shutting down VM '#{name}'..."
          wait_for_exit(pid, timeout: 30)
        else
          # Fall back to SIGTERM
          if vm['network'] == 'bridged' && macos?
            system('sudo', 'kill', '-TERM', pid.to_s)
          else
            Process.kill('TERM', pid)
          end
          puts "Sent shutdown signal to VM '#{name}' (PID #{pid})"
          wait_for_exit(pid, timeout: 30)
        end
      end
    rescue Errno::ESRCH
      puts "VM '#{name}' is already stopped."
    end

    # Clean up state and temp files
    registry.unregister(name)
    cleanup_vm_files(vm)
  end

  private

  def macos?
    RUBY_PLATFORM.include?('darwin')
  end

  def try_ssh_shutdown(vm)
    build = Pim::Build.find(vm['build_id'])
    host, port = ssh_target(vm)
    return false unless host

    ssh = Pim::SSHConnection.new(
      host: host,
      port: port,
      user: build.ssh_user,
      password: build.resolved_profile.resolve('password')
    )
    ssh.execute('shutdown -h now', sudo: true)
    true
  rescue StandardError
    false
  end

  def ssh_target(vm)
    if vm['network'] == 'bridged' && vm['bridge_ip']
      [vm['bridge_ip'], 22]
    elsif vm['ssh_port']
      ['127.0.0.1', vm['ssh_port']]
    else
      [nil, nil]
    end
  end

  def wait_for_exit(pid, timeout: 30)
    deadline = Time.now + timeout
    while Time.now < deadline
      begin
        Process.kill(0, pid)
        sleep 1
      rescue Errno::ESRCH, Errno::EPERM
        return true
      end
    end
    false
  end

  def cleanup_vm_files(vm)
    # Clean up EFI vars temp file if it exists
    efi_vars = "#{vm['image_path']}-efivars.fd"
    FileUtils.rm_f(efi_vars) if File.exist?(efi_vars)
  end
end
```

### Step 5: Add `VmCommand::Ssh`

```ruby
class Ssh < self
  desc "SSH into a running VM"

  argument :identifier, required: true, desc: "VM number (from 'vm list') or name"

  def call(identifier:, **)
    require_relative "../services/vm_registry"

    registry = Pim::VmRegistry.new
    vm = registry.find(identifier)

    unless vm
      Pim.exit!(1, message: "VM '#{identifier}' not found. Run 'pim vm list' to see running VMs.")
    end

    build = Pim::Build.find(vm['build_id'])
    host, port = ssh_target(vm)

    unless host
      Pim.exit!(1, message: "Cannot determine SSH target for VM '#{vm['name']}'. " \
                             "For bridged VMs, the IP may not have been discovered yet.")
    end

    # Build SSH command and exec into it (replaces current process)
    ssh_cmd = ['ssh',
               '-o', 'StrictHostKeyChecking=no',
               '-o', 'UserKnownHostsFile=/dev/null',
               '-o', 'LogLevel=ERROR']
    ssh_cmd += ['-p', port.to_s] if port != 22
    ssh_cmd << "#{build.ssh_user}@#{host}"

    exec(*ssh_cmd)
  end

  private

  def ssh_target(vm)
    if vm['network'] == 'bridged' && vm['bridge_ip']
      [vm['bridge_ip'], 22]
    elsif vm['ssh_port']
      ['127.0.0.1', vm['ssh_port']]
    else
      [nil, nil]
    end
  end
end
```

### Step 6: Register all commands in CLI

```ruby
# VMs
register "vm run",           VmCommand::Run
register "vm list",          VmCommand::List, aliases: ["ls"]
register "vm stop",          VmCommand::Stop
register "vm ssh",           VmCommand::Ssh
```

## Test Spec

### Unit tests

**File:** `spec/services/vm_registry_spec.rb`

- `#register` creates a YAML state file in runtime dir
- `#list` returns only VMs with alive PIDs
- `#list` prunes state files for dead PIDs
- `#find("1")` returns first VM by index
- `#find("default-arm64")` returns VM by name
- `#unique_name` appends counter for duplicates
- `#unregister` removes state file

**File:** `spec/commands/vm_command_spec.rb` (extend)

- `VmCommand::List` is registered at `vm list` with alias `ls`
- `VmCommand::Stop` is registered at `vm stop`
- `VmCommand::Ssh` is registered at `vm ssh`
- Stop with unknown identifier prints error

### Manual verification

```bash
# Start a VM in background
pim vm run default-arm64

# List running VMs
pim vm list
# Should show: #1  default-arm64  <pid>  user  ssh -p 2222 ansible@localhost

# SSH into it
pim vm ssh 1

# Stop it
pim vm stop 1

# Verify it's gone
pim vm list
# Should show: No running VMs.

# Start two VMs
pim vm run default-arm64
pim vm run default-arm64
pim vm list
# Should show: #1 default-arm64, #2 default-arm64-2

# Stop by name
pim vm stop default-arm64-2
```

## Verification

- [ ] `pim vm list` shows running VMs with index, name, PID, network, SSH info
- [ ] `pim vm list` prunes dead VMs automatically
- [ ] `pim vm stop 1` gracefully shuts down VM by index
- [ ] `pim vm stop default-arm64` stops VM by name
- [ ] `pim vm stop 1 --force` force-kills the VM
- [ ] `pim vm ssh 1` opens interactive SSH session
- [ ] State files cleaned up after stop
- [ ] Multiple VMs get unique names (auto-increment)
- [ ] Bridged VMs show IP or MAC in list
- [ ] `pim vm stop` on bridged macOS VM uses `sudo kill`
- [ ] `bundle exec rspec` passes
