---
---

# Plan 1: Test Harness — Configurable NetbootService, Bridge, QEMU, Teardown

**Tier:** E2E
**Objective:** Make `NetbootService.netboot_dir` configurable, then build the reusable infrastructure classes that all e2e tests depend on — isolated network bridge, QEMU VM launcher, SSH verification helper, and ephemeral project scaffolding. All test artifacts consolidated under a single root (`/tmp/pcs-e2e/`).
**Depends on:** Nothing. This plan is the starting point.
**Required before:** Plan 2 (PXE Handshake)

---

## Context for Claude Code

Read these files before writing any code:
- `CLAUDE.md` — gem architecture, conventions
- `docs/e2e/README.md` — tier overview, architecture, network layout, filesystem layout
- `lib/pcs/services/netboot_service.rb` — current hardcoded `NETBOOT_DIR`
- `lib/pcs/adapters/system_cmd.rb` — local command execution wrapper
- `lib/pcs/adapters/ssh.rb` — SSH connection patterns
- `lib/pcs/platform.rb` + `lib/pcs/platform/linux.rb` — platform detection (e2e is Linux-only)

---

## What This Plan Builds

### Part A: Configurable NetbootService

**File to modify:** `lib/pcs/services/netboot_service.rb`

Replace the hardcoded constant with a class-level accessor:

```ruby
class NetbootService
  DEFAULT_NETBOOT_DIR = Pathname.new("/var/lib/pcs/netboot")

  class << self
    attr_writer :netboot_dir

    def netboot_dir
      @netboot_dir || DEFAULT_NETBOOT_DIR
    end

    def reset_netboot_dir!
      @netboot_dir = nil
    end
  end
end
```

Then replace every reference to `NETBOOT_DIR` in the file with `netboot_dir`. The constant references are:

- `NETBOOT_DIR.mkpath` → `netboot_dir.mkpath`
- `NETBOOT_DIR / "menus"` → `netboot_dir / "menus"`
- `NETBOOT_DIR / "assets"` → `netboot_dir / "assets"`
- All other `NETBOOT_DIR` occurrences in `start`, `reload`, `debug`, `generate_menu`, `download_boot_files`, `generate_preseed_files`

Remove the `NETBOOT_DIR` constant entirely. Keep `TEMPLATE_DIR`, `MENU_TEMPLATE`, `MAC_TEMPLATE`, `PRESEED_TEMPLATE`, `POST_INSTALL_TEMPLATE` as-is — those point to the gem's source templates, not runtime output.

**Backward compatible:** When `netboot_dir` is never set, it returns the default `/var/lib/pcs/netboot`. Existing behavior is identical.

### Part B: E2E Root and Directory Helpers

**File: `test/e2e/support/e2e_root.rb`**

Central constant and directory helpers so every support class references the same root.

```ruby
# frozen_string_literal: true

require "pathname"

module Pcs
  module E2E
    E2E_ROOT = Pathname.new("/tmp/pcs-e2e")

    # Subdirectory paths — all under E2E_ROOT
    DIRS = {
      project:  E2E_ROOT / "project",
      netboot:  E2E_ROOT / "netboot",
      disk:     E2E_ROOT / "disk",
      logs:     E2E_ROOT / "logs",
      ssh:      E2E_ROOT / "project" / ".ssh"
    }.freeze

    def self.setup_dirs!
      DIRS.each_value(&:mkpath)
    end

    def self.cleanup!
      E2E_ROOT.rmtree if E2E_ROOT.exist?
    end
  end
end
```

### Part C: Support Classes

All support classes use `E2E_ROOT` subdirectories instead of scattered `/tmp` paths.

**File: `test/e2e/support/test_bridge.rb`**

Manages the lifecycle of an isolated Linux bridge + tap device. Unchanged from the original design — the bridge doesn't create any files.

```ruby
# frozen_string_literal: true

module Pcs
  module E2E
    class TestBridge
      BRIDGE_NAME = "pcs-test0"
      TAP_NAME = "pcs-tap0"
      BRIDGE_IP = "10.99.0.1/24"
      SUBNET = "10.99.0.0/24"

      def initialize(system_cmd: Pcs::Adapters::SystemCmd.new)
        @cmd = system_cmd
      end

      def up
        return if bridge_exists?

        @cmd.run!("ip link add #{BRIDGE_NAME} type bridge", sudo: true)
        @cmd.run!("ip addr add #{BRIDGE_IP} dev #{BRIDGE_NAME}", sudo: true)
        @cmd.run!("ip link set #{BRIDGE_NAME} up", sudo: true)

        @cmd.run!("ip tuntap add dev #{TAP_NAME} mode tap", sudo: true)
        @cmd.run!("ip link set #{TAP_NAME} master #{BRIDGE_NAME}", sudo: true)
        @cmd.run!("ip link set #{TAP_NAME} up", sudo: true)

        @cmd.run!("sysctl -w net.ipv4.ip_forward=1", sudo: true)
      end

      def down
        @cmd.run("ip link set #{TAP_NAME} down", sudo: true)
        @cmd.run("ip tuntap del dev #{TAP_NAME} mode tap", sudo: true)
        @cmd.run("ip link set #{BRIDGE_NAME} down", sudo: true)
        @cmd.run("ip link del #{BRIDGE_NAME}", sudo: true)
      end

      def bridge_exists?
        @cmd.run("ip link show #{BRIDGE_NAME}").success?
      end

      def bridge_ip
        BRIDGE_IP.split("/").first
      end
    end
  end
end
```

**File: `test/e2e/support/qemu_launcher.rb`**

QEMU VM lifecycle. Disk and logs now under `E2E_ROOT`.

```ruby
# frozen_string_literal: true

require "pathname"
require_relative "e2e_root"

module Pcs
  module E2E
    class QemuLauncher
      DEFAULT_DISK_SIZE = "10G"
      DEFAULT_RAM = "1024"
      DEFAULT_CPUS = "2"

      def initialize(
        tap: TestBridge::TAP_NAME,
        system_cmd: Pcs::Adapters::SystemCmd.new
      )
        @tap = tap
        @cmd = system_cmd
        @pid = nil
      end

      def start_pxe(name: "pcs-e2e-node", ram: DEFAULT_RAM, cpus: DEFAULT_CPUS,
                     disk_size: DEFAULT_DISK_SIZE)
        prepare_disk(name, disk_size)

        args = base_args(name, ram, cpus) + [
          "-boot", "n",
          "-drive", "file=#{disk_path(name)},format=qcow2,if=virtio"
        ]

        launch(args)
      end

      def start_disk(name: "pcs-e2e-node", ram: DEFAULT_RAM, cpus: DEFAULT_CPUS)
        args = base_args(name, ram, cpus) + [
          "-boot", "c",
          "-drive", "file=#{disk_path(name)},format=qcow2,if=virtio"
        ]

        launch(args)
      end

      def stop
        return unless @pid

        Process.kill("TERM", @pid)
        Process.wait(@pid)
        @pid = nil
      rescue Errno::ESRCH, Errno::ECHILD
        @pid = nil
      end

      def running?
        return false unless @pid

        Process.kill(0, @pid)
        true
      rescue Errno::ESRCH
        false
      end

      attr_reader :pid

      def cleanup_disk(name: "pcs-e2e-node")
        path = disk_path(name)
        path.delete if path.exist?
      end

      private

      def base_args(name, ram, cpus)
        accel = File.exist?("/dev/kvm") ? "kvm" : "tcg"

        [
          "qemu-system-x86_64",
          "-name", name,
          "-machine", "q35,accel=#{accel}",
          "-cpu", accel == "kvm" ? "host" : "qemu64",
          "-m", ram,
          "-smp", cpus,
          "-nographic",
          "-serial", "mon:stdio",
          "-nic", "tap,ifname=#{@tap},script=no,downscript=no,model=virtio-net-pci"
        ]
      end

      def prepare_disk(name, size)
        DIRS[:disk].mkpath
        path = disk_path(name)
        return if path.exist?

        result = @cmd.run!("qemu-img create -f qcow2 #{path} #{size}")
        raise "Failed to create disk: #{result.stderr}" unless result.success?
      end

      def disk_path(name)
        DIRS[:disk] / "#{name}.qcow2"
      end

      def launch(args)
        log_path = DIRS[:logs] / "qemu.log"
        DIRS[:logs].mkpath

        @pid = Process.spawn(
          *args,
          in: "/dev/null",
          out: log_path.to_s,
          err: log_path.to_s
        )

        sleep 2

        unless running?
          raise "QEMU failed to start. Check #{log_path}"
        end

        @pid
      end
    end
  end
end
```

**File: `test/e2e/support/ssh_verifier.rb`**

Unchanged — no file I/O, just SSH commands. Same as original design.

```ruby
# frozen_string_literal: true

require "open3"
require "socket"

module Pcs
  module E2E
    class SshVerifier
      DEFAULT_TIMEOUT = 300
      POLL_INTERVAL = 10

      def initialize(host:, user: "admin", key_path: nil)
        @host = host
        @user = user
        @key_path = key_path
      end

      def wait_for_ssh(timeout: DEFAULT_TIMEOUT)
        deadline = Time.now + timeout

        loop do
          raise "SSH to #{@host} not available after #{timeout}s" if Time.now > deadline

          if port_open?(@host, 22)
            begin
              run("echo ok")
              return true
            rescue StandardError
              # not ready yet
            end
          end

          sleep POLL_INTERVAL
        end
      end

      def run(command)
        ssh_args = [
          "ssh",
          "-o", "StrictHostKeyChecking=no",
          "-o", "UserKnownHostsFile=/dev/null",
          "-o", "ConnectTimeout=5",
          "-o", "BatchMode=yes"
        ]
        ssh_args += ["-i", @key_path] if @key_path
        ssh_args += ["#{@user}@#{@host}", command]

        stdout, stderr, status = Open3.capture3(*ssh_args)
        raise "SSH command failed: #{command}\nstderr: #{stderr}" unless status.success?

        stdout.strip
      end

      def assert_hostname(expected)
        actual = run("hostname -f")
        raise "Hostname mismatch: expected #{expected}, got #{actual}" unless actual == expected
        true
      end

      def assert_ip(interface, expected)
        actual = run("ip -4 addr show #{interface} | grep -oP 'inet \\K[\\d.]+'")
        raise "IP mismatch on #{interface}: expected #{expected}, got #{actual}" unless actual == expected
        true
      end

      def assert_file_exists(path)
        run("test -f #{path}")
        true
      rescue StandardError
        raise "File not found: #{path}"
      end

      def assert_file_contains(path, pattern)
        run("grep -q '#{pattern}' #{path}")
        true
      rescue StandardError
        raise "Pattern '#{pattern}' not found in #{path}"
      end

      def assert_service_active(service_name)
        actual = run("systemctl is-active #{service_name}")
        raise "Service #{service_name} is #{actual}, expected active" unless actual == "active"
        true
      end

      private

      def port_open?(host, port)
        Socket.tcp(host, port, connect_timeout: 3) { true }
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
             Errno::ETIMEDOUT, SocketError
        false
      end
    end
  end
end
```

**File: `test/e2e/support/test_project.rb`**

Scaffolds an ephemeral PCS project under `E2E_ROOT/project/`. Also configures `NetbootService.netboot_dir` to point at `E2E_ROOT/netboot/`.

```ruby
# frozen_string_literal: true

require "yaml"
require_relative "e2e_root"

module Pcs
  module E2E
    class TestProject
      SITE_NAME = "e2e"
      VM_HOSTNAME = "e2e-node1"
      VM_MAC = "52:54:00:e2:e2:01"
      VM_STATIC_IP = "10.99.0.41"
      OPS_IP = TestBridge::BRIDGE_IP.split("/").first

      def initialize(base_dir: DIRS[:project])
        @base_dir = base_dir
      end

      def scaffold
        cleanup
        E2E.setup_dirs!

        # Use pcs new to scaffold, then overlay test data
        system_cmd = Pcs::Adapters::SystemCmd.new
        Dir.chdir(@base_dir.parent) do
          system_cmd.run!("pcs new #{@base_dir.basename}")
        end

        write_site_config
        write_host_data
        write_service_data
        write_env
        generate_ssh_keys

        # Point NetbootService at test-local directory
        Pcs::Services::NetbootService.netboot_dir = DIRS[:netboot]

        @base_dir
      end

      def project_dir
        @base_dir
      end

      def ssh_private_key_path
        DIRS[:ssh] / "e2e_key"
      end

      def cleanup
        # Reset NetbootService to default
        Pcs::Services::NetbootService.reset_netboot_dir! if defined?(Pcs::Services::NetbootService)

        E2E.cleanup!
      end

      private

      def write_site_config
        site_dir = @base_dir / "sites" / SITE_NAME
        site_dir.mkpath

        site_yml = {
          "name" => SITE_NAME,
          "domain" => "e2e.test",
          "timezone" => "UTC",
          "ssh_key" => (DIRS[:ssh] / "authorized_keys").to_s,
          "networks" => {
            "compute" => {
              "subnet" => "10.99.0.0/24",
              "gateway" => "10.99.0.1",
              "dns_resolvers" => ["10.99.0.1", "1.1.1.1"]
            },
            "storage" => {
              "subnet" => "10.99.1.0/24",
              "gateway" => "10.99.1.1",
              "dns_resolvers" => ["10.99.1.1"]
            }
          }
        }

        (site_dir / "site.yml").write(YAML.dump(site_yml))
      end

      def write_host_data
        site_dir = @base_dir / "sites" / SITE_NAME
        hosts_yml = {
          "records" => [
            {
              "id" => "1",
              "hostname" => VM_HOSTNAME,
              "mac" => VM_MAC,
              "type" => "proxmox",
              "role" => "node",
              "status" => "discovered",
              "connect_as" => "admin",
              "discovered_ip" => VM_STATIC_IP,
              "compute_ip" => VM_STATIC_IP,
              "site_id" => SITE_NAME,
              "discovered_at" => Time.now.iso8601,
              "last_seen_at" => Time.now.iso8601
            }
          ]
        }

        (site_dir / "hosts.yml").write(YAML.dump(hosts_yml))
      end

      def write_service_data
        data_dir = @base_dir / "data"
        data_dir.mkpath

        services_yml = {
          "records" => [
            {
              "name" => "netbootxyz",
              "image" => "docker.io/netbootxyz/netbootxyz",
              "debian_kernel" => "http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux",
              "debian_initrd" => "http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz",
              "ipxe_timeout" => 10
            }
          ]
        }

        (data_dir / "services.yml").write(YAML.dump(services_yml))
      end

      def write_env
        (@base_dir / ".env").write("PCS_SITE=#{SITE_NAME}\n")
      end

      def generate_ssh_keys
        DIRS[:ssh].mkpath
        private_key = DIRS[:ssh] / "e2e_key"
        public_key = DIRS[:ssh] / "e2e_key.pub"
        authorized_keys = DIRS[:ssh] / "authorized_keys"

        unless private_key.exist?
          system("ssh-keygen -t ed25519 -f #{private_key} -N '' -q")
          authorized_keys.write(public_key.read)
        end
      end
    end
  end
end
```

**File: `test/e2e/teardown.rb`**

Standalone teardown. Cleans everything under `E2E_ROOT`.

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone teardown — safe to run anytime
require_relative "support/e2e_root"
require_relative "support/test_bridge"
require_relative "support/qemu_launcher"

# Kill any running QEMU instances from e2e
`pgrep -f pcs-e2e`.split("\n").each do |pid|
  Process.kill("TERM", pid.to_i) rescue nil
end

Pcs::E2E::TestBridge.new.down
Pcs::E2E.cleanup!

puts "Teardown complete."
```

**File: `bin/e2e`**

Runner script. Unchanged except log path references in help text.

```bash
#!/usr/bin/env bash
set -euo pipefail

TIER="${1:-handshake}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GEM_DIR="$(dirname "$SCRIPT_DIR")"

if [[ "$(uname)" != "Linux" ]]; then
  echo "Error: E2E tests require Linux (bridge/tap networking)."
  echo "Run on the RPi or a Linux dev VM."
  exit 1
fi

for cmd in qemu-system-x86_64 ip dnsmasq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd not found. Install with:"
    echo "  sudo apt-get install -y qemu-system-x86 dnsmasq-base bridge-utils iproute2"
    exit 1
  fi
done

echo "=== PCS E2E Test Runner (tier: $TIER) ==="
echo

cleanup() {
  echo
  echo "=== Teardown ==="
  cd "$GEM_DIR" && bundle exec ruby test/e2e/teardown.rb 2>/dev/null || true
}
trap cleanup EXIT

cd "$GEM_DIR"
case "$TIER" in
  handshake)
    bundle exec ruby test/e2e/pxe_handshake_test.rb
    ;;
  full)
    bundle exec ruby test/e2e/full_install_test.rb
    ;;
  *)
    echo "Unknown tier: $TIER"
    echo "Usage: bin/e2e [handshake|full]"
    exit 1
    ;;
esac
```

---

## Implementation Spec

### Part A: NetbootService change

1. Open `lib/pcs/services/netboot_service.rb`
2. Remove `NETBOOT_DIR = Pathname.new("/var/lib/pcs/netboot")`
3. Add `DEFAULT_NETBOOT_DIR = Pathname.new("/var/lib/pcs/netboot")`
4. Add class-level `netboot_dir` accessor and `reset_netboot_dir!`
5. Replace all `NETBOOT_DIR` references with `netboot_dir`
6. Verify existing specs still pass — behavior is identical when accessor is not set

### Part B: E2E harness

1. Create `test/e2e/support/` directory
2. Write `e2e_root.rb` — `E2E_ROOT` constant, `DIRS` hash, `setup_dirs!`, `cleanup!`
3. Write `test_bridge.rb` — bridge/tap lifecycle
4. Write `qemu_launcher.rb` — QEMU start/stop, disk/logs under `DIRS[:disk]` and `DIRS[:logs]`
5. Write `ssh_verifier.rb` — SSH wait + assertion helpers
6. Write `test_project.rb` — scaffold under `DIRS[:project]`, sets `NetbootService.netboot_dir = DIRS[:netboot]`
7. Write `test/e2e/teardown.rb` — calls `E2E.cleanup!` and `TestBridge#down`
8. Write `bin/e2e` — runner with pre-flight checks and EXIT trap
9. `chmod +x bin/e2e`

---

## Verification

```bash
# On a Linux host:

# 1. NetbootService accessor works
ruby -e '
  require_relative "lib/pcs"
  puts Pcs::Services::NetbootService.netboot_dir
  # => /var/lib/pcs/netboot

  Pcs::Services::NetbootService.netboot_dir = Pathname.new("/tmp/test-netboot")
  puts Pcs::Services::NetbootService.netboot_dir
  # => /tmp/test-netboot

  Pcs::Services::NetbootService.reset_netboot_dir!
  puts Pcs::Services::NetbootService.netboot_dir
  # => /var/lib/pcs/netboot
'

# 2. E2E root setup/cleanup
ruby -e '
  require_relative "test/e2e/support/e2e_root"
  Pcs::E2E.setup_dirs!
  puts `find /tmp/pcs-e2e -type d`
  Pcs::E2E.cleanup!
  puts "OK: dirs created and cleaned"
'

# 3. Bridge lifecycle
sudo ruby -e '
  require_relative "test/e2e/support/test_bridge"
  b = Pcs::E2E::TestBridge.new
  b.up
  puts `ip addr show pcs-test0`
  b.down
  puts "OK"
'

# 4. QEMU launches (will fail PXE — no server — but process starts)
ruby -e '
  require_relative "test/e2e/support/e2e_root"
  require_relative "test/e2e/support/test_bridge"
  require_relative "test/e2e/support/qemu_launcher"
  Pcs::E2E.setup_dirs!
  q = Pcs::E2E::QemuLauncher.new
  q.start_pxe
  sleep 3
  puts q.running? ? "OK: QEMU running (pid #{q.pid})" : "FAIL"
  q.stop
  q.cleanup_disk
  Pcs::E2E.cleanup!
'

# 5. Verify no files outside /tmp/pcs-e2e
find /var/lib/pcs /tmp -name "*e2e*" -not -path "/tmp/pcs-e2e/*" 2>/dev/null
# Should return nothing
```
