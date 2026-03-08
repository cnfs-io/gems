---
---

# Plan 02 — Bridged Networking

## Context

Read before starting:
- `docs/vm-runner/README.md` — tier overview
- `docs/vm-runner/plan-01-vm-run.md` — plan 01 (must be complete)
- `lib/pim/services/qemu_command_builder.rb` — needs `add_bridged_net` method
- `lib/pim/services/vm_runner.rb` — needs bridged networking path
- `lib/pim/commands/vm_command.rb` — needs `--bridged` flag
- `CLAUDE.md` — documents existing bridged networking conventions (vmnet-bridged, sudo, root ownership)

## Goal

Add `--bridged` flag to `pim vm run` so the VM gets a real LAN IP instead of using port-forwarded user-mode networking. Must work on both macOS (vmnet-bridged) and Linux (tap + bridge).

## Background

From CLAUDE.md — bridged networking conventions already established for builds:
- macOS: `vmnet-bridged` on `en0`, QEMU runs as root via `sudo`, all sockets/PIDs are root-owned
- Linux: tap device attached to a bridge (typically `br0`), requires `sudo` for tap creation
- VM gets a LAN IP — SSH directly to that IP, no port forwarding

The main challenge is IP discovery — when the VM boots with bridged networking, we don't know its IP until it gets a DHCP lease. Options:
1. Guest agent query (`guest-network-get-interfaces`) — requires qemu-guest-agent in the image
2. ARP table scan after boot — `arp -a` or `ip neigh` looking for the VM's MAC
3. DHCP lease inspection — if we control the DHCP server (we do on PCS sites, but not always)
4. Wait for SSH banner on discovered IPs — slow but universal

Strategy: Use guest agent as primary (images already include `qemu-guest-agent` per CLAUDE.md), fall back to printing the MAC address so the user can find the IP manually.

## Implementation

### Step 1: Extend `QemuCommandBuilder` with bridged networking

Add method `add_bridged_net` to `QemuCommandBuilder`:

```ruby
# Add bridged networking
# macOS: vmnet-bridged via en0
# Linux: tap device (auto-created, attached to bridge)
def add_bridged_net(id: 'net0', bridge: nil, mac: nil)
  @netdevs << {
    type: 'bridged',
    id: id,
    bridge: bridge,
    mac: mac || generate_mac
  }
  self
end

private

def generate_mac
  # Generate a locally-administered MAC (bit 1 of first octet set)
  # 52:54:00 is QEMU's conventional OUI prefix
  "52:54:00:%02x:%02x:%02x" % [rand(256), rand(256), rand(256)]
end
```

In the `build` method, handle the `bridged` type in the network loop:

```ruby
when 'bridged'
  if macos?
    # vmnet-bridged — requires sudo, VM gets LAN IP
    cmd += ['-nic', "vmnet-bridged,id=#{net[:id]},mac=#{net[:mac]}"]
  else
    # Linux tap + bridge
    bridge = net[:bridge] || 'br0'
    # QEMU's built-in bridge helper or manual tap
    cmd += ['-netdev', "bridge,id=#{net[:id]},br=#{bridge}"]
    cmd += ['-device', "#{virtio_net_device},netdev=#{net[:id]},mac=#{net[:mac]}"]
  end
```

**Note:** On macOS, `-nic vmnet-bridged` is the modern syntax (QEMU 7+). On Linux, the `bridge` netdev helper requires `/etc/qemu/bridge.conf` to allow the bridge. If that's not set up, fall back to tap creation via a helper script. Check which approach works on the Pi.

### Step 2: Add `--bridged` flag to `VmCommand::Run`

```ruby
option :bridged, type: :boolean, default: false,
       desc: "Use bridged networking (VM gets LAN IP, requires sudo)"
option :bridge, type: :string, default: nil,
       desc: "Bridge device for bridged networking (default: br0, Linux only)"
```

Pass through to `VmRunner#run`:

```ruby
runner.run(
  snapshot: snapshot,
  clone: clone,
  console: console,
  memory: memory,
  cpus: cpus,
  bridged: bridged,
  bridge: bridge
)
```

### Step 3: Update `VmRunner` for bridged mode

Key changes to `VmRunner#run` and `#build_qemu_command`:

```ruby
def run(snapshot: true, clone: false, console: false, memory: nil, cpus: nil,
        bridged: false, bridge: nil)
  @bridged = bridged
  @bridge = bridge
  @mac = nil  # set during command building

  # ... existing image preparation ...

  if bridged
    # No port forwarding needed — VM gets LAN IP
    @ssh_port = nil
    builder = build_qemu_command(
      memory: memory || @build.memory,
      cpus: cpus || @build.cpus,
      snapshot: snapshot,
      bridged: true,
      bridge: bridge
    )
  else
    @ssh_port = Pim::Qemu.find_available_port
    builder = build_qemu_command(
      memory: memory || @build.memory,
      cpus: cpus || @build.cpus,
      snapshot: snapshot
    )
  end

  # ... existing VM start logic ...
  # For bridged on macOS, must use sudo
  if bridged && macos?
    # Prepend sudo to command
    cmd = ['sudo'] + builder.build
    @vm = Pim::QemuVM.new(command: cmd, ssh_port: nil)
  else
    @vm = Pim::QemuVM.new(command: builder.build, ssh_port: @ssh_port)
  end

  # ... start VM ...
end
```

Update `#build_qemu_command` to use `add_bridged_net` or `add_user_net`:

```ruby
def build_qemu_command(memory:, cpus:, snapshot:, bridged: false, bridge: nil)
  builder = Pim::QemuCommandBuilder.new(
    arch: @arch,
    memory: memory,
    cpus: cpus,
    display: false,
    serial: nil
  )

  builder.add_drive(@image_path, format: 'qcow2')

  if bridged
    @mac = nil  # let builder generate
    builder.add_bridged_net(bridge: bridge)
    # Add guest agent channel for IP discovery
    add_guest_agent_channel(builder)
  else
    builder.add_user_net(host_port: @ssh_port, guest_port: 22)
  end

  builder.extra_args('-snapshot') if snapshot
  setup_efi(builder) if @arch == 'arm64'

  builder
end
```

### Step 4: Guest agent channel for IP discovery

Add a virtio-serial channel for the guest agent so we can query the VM's IP:

```ruby
def add_guest_agent_channel(builder)
  runtime_dir = Pim::Qemu.runtime_dir
  socket_path = File.join(runtime_dir, "#{@name}.ga")

  builder.extra_args(
    '-device', 'virtio-serial-pci',
    '-chardev', "socket,path=#{socket_path},server=on,wait=off,id=ga0",
    '-device', 'virtserialport,chardev=ga0,name=org.qemu.guest_agent.0'
  )

  @ga_socket = socket_path
end
```

Add IP discovery method:

```ruby
def discover_ip(timeout: 30)
  return nil unless @ga_socket

  deadline = Time.now + timeout
  while Time.now < deadline
    begin
      # Query guest agent for network interfaces
      cmd = if macos?
        ['sudo', 'socat', '-', "UNIX-CONNECT:#{@ga_socket}"]
      else
        ['socat', '-', "UNIX-CONNECT:#{@ga_socket}"]
      end

      # Send query with sleep for agent response time
      query = '{"execute":"guest-network-get-interfaces"}'
      output, status = Open3.capture2(*cmd, stdin_data: "#{query}\n", timeout: 5)

      if status.success? && output.include?('"ip-address"')
        # Parse response, find non-loopback IPv4 address
        data = JSON.parse(output.lines.last)
        if data['return']
          data['return'].each do |iface|
            next if iface['name'] == 'lo'
            iface['ip-addresses']&.each do |addr|
              if addr['ip-address-type'] == 'ipv4'
                return addr['ip-address']
              end
            end
          end
        end
      end
    rescue StandardError
      # Agent not ready yet
    end

    sleep 2
  end

  nil
end
```

### Step 5: Update `print_connection_info` for bridged mode

```ruby
def print_connection_info
  puts "VM: #{@name}"
  puts "  PID:     #{@vm.pid}"
  puts "  Arch:    #{@arch}"
  puts "  Image:   #{@image_path}"

  if @bridged
    puts "  Network: bridged"
    puts "  MAC:     #{@mac}" if @mac
    # Try to discover IP (give guest agent a moment)
    ip = discover_ip(timeout: 30)
    if ip
      puts "  IP:      #{ip}"
      puts "  SSH:     ssh #{@build.ssh_user}@#{ip}"
    else
      puts "  IP:      (discovering... check 'arp -a' or router DHCP leases)"
      puts "  MAC:     #{@mac} (use to find IP)"
    end
  else
    puts "  SSH:     ssh -p #{@ssh_port} #{@build.ssh_user}@localhost"
    puts "  Network: user (port forwarding)"
  end
end
```

### Step 6: Add `Pim::Qemu.runtime_dir` if not present

```ruby
def self.runtime_dir
  dir = if ENV['XDG_RUNTIME_DIR']
    File.join(ENV['XDG_RUNTIME_DIR'], 'pim')
  else
    File.join('/tmp', 'pim')
  end
  FileUtils.mkdir_p(dir)
  dir
end
```

### Step 7: Linux bridge helper setup

On Linux, QEMU's bridge helper needs permission. Check/create `/etc/qemu/bridge.conf`:

This is a documentation concern, not a code change. Add a note to the `--bridged` help text:

```
Linux: requires bridge device (default: br0) and /etc/qemu/bridge.conf with 'allow br0'.
macOS: requires sudo for vmnet-bridged.
```

If the bridge helper doesn't work on the Pi, fall back to manual tap creation:
```ruby
# Fallback: create tap manually
cmd += ['-netdev', "tap,id=#{net[:id]},script=no,downscript=no"]
# Tap must be pre-created and attached to bridge by user
```

Document both approaches; prefer the bridge helper.

## Test Spec

### Unit tests

**File:** `spec/services/qemu_command_builder_spec.rb` (extend)

- `#add_bridged_net` generates a MAC address
- `#build` with bridged net produces `vmnet-bridged` args on macOS
- `#build` with bridged net produces `bridge` netdev args on Linux
- `#add_bridged_net(bridge: 'br1')` uses custom bridge name

**File:** `spec/services/vm_runner_spec.rb` (extend)

- `#run(bridged: true)` does not set `@ssh_port`
- `#run(bridged: true)` on macOS prepends `sudo` to command
- Guest agent channel is added for bridged mode

### Manual verification

```bash
# macOS — bridged (will prompt for sudo)
pim vm run default-arm64 --bridged --console

# Linux — bridged with default br0
pim vm run default-arm64 --bridged --console

# Linux — bridged with custom bridge
pim vm run default-arm64 --bridged --bridge br1 --console

# Verify IP discovery
pim vm run default-arm64 --bridged
# Should print discovered IP after a few seconds
```

## Verification

- [ ] `pim vm run default-arm64 --bridged --console` boots with bridged networking on macOS
- [ ] `pim vm run default-arm64 --bridged --console` boots with bridged networking on Linux
- [ ] VM gets a LAN IP (visible in `arp -a` or router DHCP table)
- [ ] Guest agent IP discovery works (prints IP in connection info)
- [ ] MAC address is printed when IP discovery fails
- [ ] `sudo` is used automatically on macOS for bridged mode
- [ ] `--bridge br1` overrides default bridge device on Linux
- [ ] Non-bridged mode still works as before (regression)
- [ ] `bundle exec rspec` passes
