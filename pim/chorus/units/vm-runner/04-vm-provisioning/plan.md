---
---

# Plan 04 — VM Provisioning (--run / --run-and-stay)

## Context

Read before starting:
- `docs/vm-runner/README.md` — tier overview
- `docs/vm-runner/plan-01-vm-run.md` — plan 01 (must be complete)
- `docs/vm-runner/plan-03-vm-lifecycle.md` — plan 03 (must be complete)
- `lib/pim/services/vm_runner.rb` — current runner (add provisioning support)
- `lib/pim/services/ssh_connection.rb` — existing SSH/SCP wrapper
- `lib/pim/services/verifier.rb` — reference for script upload + execute pattern

## Goal

Add `--run SCRIPT` and `--run-and-stay SCRIPT` flags to `pim vm run` so that after the VM boots and SSH is available, a local script is uploaded and executed on the VM. This enables ansible-like provisioning without requiring ansible.

- `--run SCRIPT`: boot → wait for SSH → upload + execute script → shut down VM
- `--run-and-stay SCRIPT`: boot → wait for SSH → upload + execute script → keep VM running

## Implementation

### Step 1: Add flags to `VmCommand::Run`

```ruby
option :run, type: :string, default: nil,
       desc: "Script to upload and execute after boot (shuts down VM after)"
option :run_and_stay, type: :string, default: nil,
       desc: "Script to upload and execute after boot (keeps VM running)"
```

Validation: `--run` and `--run-and-stay` are mutually exclusive. If both given, error.

The script path is relative to the project directory (or absolute). Verify the file exists before booting.

### Step 2: Add provisioning to `VmRunner`

Add a `provision` method to `VmRunner`:

```ruby
# Upload and execute a script on the running VM.
#
# Options:
#   script_path:   local path to the script
#   verbose:       stream output to terminal
#   sudo:          run with sudo (default: true)
#
# Returns: { exit_code:, stdout:, stderr: }
def provision(script_path, verbose: true, sudo: true)
  raise Error, "VM is not running" unless running?
  raise Error, "Script not found: #{script_path}" unless File.exist?(script_path)

  host, port = ssh_target
  raise Error, "Cannot determine SSH target" unless host

  puts "Waiting for SSH..."
  wait_for_ssh(host: host, port: port)

  puts "Uploading #{File.basename(script_path)}..."
  ssh = Pim::SSHConnection.new(
    host: host,
    port: port,
    user: @build.ssh_user,
    password: @profile.resolve('password')
  )

  remote_path = "/tmp/pim-provision-#{File.basename(script_path)}"
  ssh.upload(script_path, remote_path)
  ssh.execute("chmod +x #{remote_path}", sudo: sudo)

  puts "Running #{File.basename(script_path)}..."
  if verbose
    exit_code = ssh.execute_stream(remote_path, sudo: sudo) do |type, data|
      case type
      when :stdout then $stdout.write(data)
      when :stderr then $stderr.write(data)
      end
    end
    { exit_code: exit_code, stdout: '', stderr: '' }
  else
    ssh.execute(remote_path, sudo: sudo)
  end
end

private

def ssh_target
  if @bridged
    ip = @bridge_ip || discover_ip(timeout: 60)
    ip ? [ip, 22] : [nil, nil]
  else
    ['127.0.0.1', @ssh_port]
  end
end

def wait_for_ssh(host:, port:, timeout: 300)
  deadline = Time.now + timeout
  while Time.now < deadline
    begin
      Timeout.timeout(5) do
        socket = TCPSocket.new(host, port)
        banner = socket.gets
        socket.close
        return true if banner&.start_with?('SSH-')
      end
    rescue StandardError
      sleep 5
    end
  end
  raise Error, "Timed out waiting for SSH on #{host}:#{port}"
end
```

### Step 3: Update `VmCommand::Run#call` to handle provisioning

```ruby
def call(build_id:, console: false, snapshot: true, clone: false,
         name: nil, memory: nil, cpus: nil, bridged: false, bridge: nil,
         run: nil, run_and_stay: nil, **)
  # Validate
  if run && run_and_stay
    Pim.exit!(1, message: "Cannot use both --run and --run-and-stay")
  end

  script_path = run || run_and_stay
  shutdown_after = !!run  # --run shuts down, --run-and-stay doesn't

  if script_path && !File.exist?(script_path)
    Pim.exit!(1, message: "Script not found: #{script_path}")
  end

  # --run/--run-and-stay implies --no-snapshot (you probably want changes to persist)
  # unless --snapshot was explicitly given
  if script_path && snapshot && !clone
    puts "Note: --run implies --no-snapshot (changes will persist in a CoW overlay)"
    snapshot = false
  end

  # --clone implies --no-snapshot
  snapshot = false if clone

  build = Pim::Build.find(build_id)
  runner = Pim::VmRunner.new(build: build, name: name || build_id)

  # For provisioning, always background the VM (not console mode)
  if script_path
    runner.run(
      snapshot: snapshot, clone: clone, console: false,
      memory: memory, cpus: cpus, bridged: bridged, bridge: bridge
    )

    result = runner.provision(script_path, verbose: true)

    if result[:exit_code] == 0
      puts "\nProvisioning complete (exit code 0)"
    else
      puts "\nProvisioning failed (exit code #{result[:exit_code]})"
    end

    if shutdown_after
      puts "Shutting down VM..."
      runner.stop
    else
      puts "VM is still running."
      puts "Stop with: pim vm stop #{runner.instance_name}"
    end
  else
    runner.run(
      snapshot: snapshot, clone: clone, console: console,
      memory: memory, cpus: cpus, bridged: bridged, bridge: bridge
    )

    unless console
      puts "\nVM is running in the background."
      puts "Stop with: pim vm stop #{runner.instance_name}"
    end
  end
rescue FlatRecord::RecordNotFound
  Pim.exit!(1, message: "Build '#{build_id}' not found")
rescue Pim::VmRunner::Error => e
  Pim.exit!(1, message: e.message)
end
```

### Step 4: Expose `instance_name` from VmRunner

Add `attr_reader :instance_name` to `VmRunner` (set during registration in plan 03).

## Test Spec

### Unit tests

**File:** `spec/services/vm_runner_spec.rb` (extend)

- `#provision` raises if VM not running
- `#provision` raises if script doesn't exist
- `#provision` uploads script via SCP and executes via SSH
- `#ssh_target` returns localhost + port for user-mode
- `#ssh_target` returns bridge IP + 22 for bridged mode

**File:** `spec/commands/vm_command_spec.rb` (extend)

- `--run` and `--run-and-stay` are mutually exclusive
- `--run` with nonexistent script prints error
- `--run` implies `snapshot: false`

### Manual verification

```bash
# Create a simple provisioning script
cat > /tmp/test-provision.sh << 'EOF'
#!/bin/bash
set -e
echo "Hello from provisioning!"
hostname
uname -a
apt-get update -qq
echo "Provisioning complete"
EOF

# Run and shut down
pim vm run default-arm64 --run /tmp/test-provision.sh
# Should: boot, run script with streaming output, shut down

# Run and stay
pim vm run default-arm64 --run-and-stay /tmp/test-provision.sh
# Should: boot, run script, keep running
pim vm list
# Should show the VM still running
pim vm ssh 1
# Should connect

# With bridged networking
pim vm run default-arm64 --bridged --run-and-stay /tmp/test-provision.sh
```

## Verification

- [ ] `pim vm run default-arm64 --run script.sh` boots, provisions, shuts down
- [ ] `pim vm run default-arm64 --run-and-stay script.sh` boots, provisions, stays running
- [ ] Script output streams to terminal in real time
- [ ] `--run` implies `--no-snapshot` with informational message
- [ ] `--run` + `--run-and-stay` together produces error
- [ ] Nonexistent script produces error before booting
- [ ] Provisioning works with both user-mode and bridged networking
- [ ] Failed script (non-zero exit) reports failure but doesn't crash
- [ ] `bundle exec rspec` passes
