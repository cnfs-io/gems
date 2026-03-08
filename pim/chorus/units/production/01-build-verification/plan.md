---
---

# Plan 01: Build Verification (Local QEMU)

## Context

Read these files before starting:

- `lib/pim/build/local_builder.rb` — full local build pipeline (create disk → install → boot → SSH → scripts → shutdown)
- `lib/pim/build/manager.rb` — `Pim::BuildManager`, orchestrates builds from Build model records
- `lib/pim/ssh.rb` — `Pim::SSHConnection` for SSH/SCP operations
- `lib/pim/qemu.rb` — `Pim::QemuCommandBuilder`, `Pim::QemuVM`, `Pim::QemuDiskImage`, `Pim::Qemu` utility module
- `lib/pim/registry.rb` — `Pim::Registry` for image tracking
- `lib/pim/models/profile.rb` — `Pim::Profile` with `verification_script` method
- `lib/pim/models/build.rb` — `Pim::Build` model (profile + iso + distro + arch)
- `lib/pim/commands/verify.rb` — existing verify command stub
- `docs/ADR-001-pim-build-architecture.md` — architecture, runtime conventions, pipeline design

**Scope:** This plan implements verification for local QEMU builds only. Remote builder routing (Mac → remote Linux for x86_64) is a separate Production plan. The architecture resolver and remote builder infrastructure exist as stubs but are not exercised here.

## Objective

Add a `Pim::Verifier` class that boots a built image, SSHes in, runs a verification script, and reports pass/fail. Wire it to `pim verify BUILD_ID`. Add an integration test for the full build+verify cycle.

## Design

### What verification proves

Verification answers: "Does this image boot, accept SSH, and have the expected software/config?" It's the automated equivalent of manually booting a VM and checking that everything works.

### Verification flow

```
1. Resolve build record → profile → image path from registry
2. Resolve verification script (from profile or default)
3. Boot image with QEMU in snapshot mode (-snapshot)
4. Wait for SSH to become available
5. Upload verification script via SCP
6. Execute script, capture stdout/stderr/exit_code
7. Shutdown VM
8. Report result
```

### Key design decisions

**`-snapshot` flag:** CRITICAL. The image must not be modified during verification. QEMU's `-snapshot` flag redirects all writes to a temporary file that's discarded on shutdown. The built image remains byte-identical.

**Reuse build infrastructure:** Verification reuses `QemuCommandBuilder`, `QemuVM`, `SSHConnection` — the same components the build pipeline uses. The only differences:
- No installer phase (boot directly from disk)
- `-snapshot` flag added
- No preseed server needed
- Run one script (verification) instead of provisioning scripts

**Build model integration:** `pim verify BUILD_ID` looks up the Build record, resolves its profile and arch, finds the image in the registry, and runs verification. This is consistent with `pim build run BUILD_ID`.

**SSH credentials:** Come from the profile (username, password) and build config (SSH port, timeout). Same as the build pipeline's phase 2 boot.

**EFI vars for arm64:** The verify command must use the EFI vars file saved during build, otherwise arm64 VMs won't find their boot entry. Path convention: `image_path.sub(/\.qcow2$/, '-efivars.fd')`.

### Result object

```ruby
Pim::VerifyResult = Struct.new(:success, :exit_code, :stdout, :stderr, :duration, keyword_init: true)
```

## Implementation

### 1. Create `lib/pim/verifier.rb`

```ruby
# frozen_string_literal: true

require 'time'

module Pim
  VerifyResult = Struct.new(:success, :exit_code, :stdout, :stderr, :duration, keyword_init: true)

  class Verifier
    class VerifyError < StandardError; end

    def initialize(build:, config:)
      @build = build
      @config = config
      @profile = build.resolved_profile
      @arch = build.arch
      @vm = nil
      @ssh_port = nil
    end

    def verify(verbose: false)
      start_time = Time.now

      begin
        # 1. Find image
        image_path = find_image
        output "Image: #{image_path}"

        # 2. Find verification script
        script_path = find_verification_script
        output "Verification script: #{File.basename(script_path)}"

        # 3. Boot VM in snapshot mode
        boot_vm_snapshot(image_path)
        output "VM booted (PID: #{@vm.pid}, SSH port: #{@ssh_port})"

        # 4. Wait for SSH
        output "Waiting for SSH..."
        wait_for_ssh

        # 5. Upload and run verification script
        output "Running verification script..."
        result = run_verification_script(script_path, verbose: verbose)

        # 6. Shutdown
        shutdown_vm

        duration = Time.now - start_time
        VerifyResult.new(
          success: result[:exit_code] == 0,
          exit_code: result[:exit_code],
          stdout: result[:stdout],
          stderr: result[:stderr],
          duration: duration
        )
      rescue StandardError => e
        cleanup
        duration = Time.now - start_time
        VerifyResult.new(
          success: false,
          exit_code: -1,
          stdout: "",
          stderr: e.message,
          duration: duration
        )
      end
    end

    private

    def output(msg)
      puts "  #{msg}"
    end

    def find_image
      registry = Pim::Registry.new(image_dir: @config.build.image_dir)
      entry = registry.find(profile: @profile.id, arch: @arch)

      unless entry
        raise VerifyError, "No image found for #{@profile.id}-#{@arch}. Run 'pim build run' first."
      end

      path = entry['path']
      unless File.exist?(path)
        raise VerifyError, "Image file missing: #{path}"
      end

      path
    end

    def find_verification_script
      script = @profile.verification_script
      unless script
        raise VerifyError, "No verification script for profile '#{@profile.id}'. " \
                           "Create verifications.d/#{@profile.id}.sh or verifications.d/default.sh"
      end
      script
    end

    def boot_vm_snapshot(image_path)
      @ssh_port = Pim::Qemu.find_available_port

      builder = Pim::QemuCommandBuilder.new(
        arch: @arch,
        memory: @config.build.memory,
        cpus: @config.build.cpus,
        display: false,
        serial: nil
      )

      builder.add_drive(image_path, format: 'qcow2')
      builder.add_user_net(host_port: @ssh_port, guest_port: 22)
      builder.extra_args('-snapshot')  # CRITICAL: don't modify the image

      # EFI vars for arm64
      if @arch == 'arm64'
        efi_code = find_efi_firmware
        efi_vars = image_path.sub(/\.qcow2$/, '-efivars.fd')

        if efi_code && File.exist?(efi_vars)
          # Copy vars to temp file since -snapshot doesn't apply to pflash
          @temp_efi_vars = "#{efi_vars}.verify-tmp"
          FileUtils.cp(efi_vars, @temp_efi_vars)

          builder.extra_args(
            '-drive', "if=pflash,format=raw,file=#{efi_code},readonly=on",
            '-drive', "if=pflash,format=raw,file=#{@temp_efi_vars}"
          )
        end
      end

      @vm = Pim::QemuVM.new(command: builder.build, ssh_port: @ssh_port)
      @vm.start_background(detach: false)
    end

    def find_efi_firmware
      [
        '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
        '/usr/local/share/qemu/edk2-aarch64-code.fd',
        '/usr/share/qemu/edk2-aarch64-code.fd',
        '/usr/share/AAVMF/AAVMF_CODE.fd',
        '/usr/share/qemu-efi-aarch64/QEMU_EFI.fd'
      ].find { |p| File.exist?(p) }
    end

    def wait_for_ssh
      success = @vm.wait_for_ssh(timeout: @config.build.ssh_timeout, poll_interval: 5)
      raise VerifyError, "Timed out waiting for SSH (#{@config.build.ssh_timeout}s)" unless success
      sleep 3  # give services a moment to settle
    end

    def run_verification_script(script_path, verbose: false)
      ssh = Pim::SSHConnection.new(
        host: '127.0.0.1',
        port: @ssh_port,
        user: @config.build.ssh_user,
        password: @profile.resolve('password')
      )

      remote_path = '/tmp/pim-verify.sh'
      ssh.upload(script_path, remote_path)
      ssh.execute("chmod +x #{remote_path}", sudo: true)
      result = ssh.execute(remote_path, sudo: true)

      if verbose
        puts result[:stdout] unless result[:stdout].strip.empty?
        $stderr.puts result[:stderr] unless result[:stderr].strip.empty?
      end

      result
    end

    def shutdown_vm
      return unless @vm&.running?

      begin
        ssh = Pim::SSHConnection.new(
          host: '127.0.0.1',
          port: @ssh_port,
          user: @config.build.ssh_user,
          password: @profile.resolve('password')
        )
        ssh.execute('shutdown -h now', sudo: true)
        sleep 3
      rescue StandardError
        # SSH may fail during shutdown
      end

      @vm.shutdown(timeout: 30)
    end

    def cleanup
      @vm&.kill if @vm&.running?
      FileUtils.rm_f(@temp_efi_vars) if @temp_efi_vars
    end
  end
end
```

### 2. Update `pim verify` command

Rewrite `lib/pim/commands/verify.rb`:

```ruby
# frozen_string_literal: true

require "dry/cli"

module Pim
  module Commands
    class Verify < Dry::CLI::Command
      desc "Verify a built image by running its verification script"

      argument :build_id, required: true, desc: "Build recipe ID"

      option :verbose, type: :boolean, default: false, aliases: ["-v"], desc: "Show verification script output"

      def call(build_id:, verbose: false, **)
        Pim.configure_flat_record!
        config = Pim::Config.new

        build = Pim::Build.find(build_id)
        profile = build.resolved_profile

        puts "Verifying: #{build_id}"
        puts "  Profile: #{profile.id}"
        puts "  Arch:    #{build.arch}"
        puts

        require_relative "../verifier"

        verifier = Pim::Verifier.new(build: build, config: config)
        result = verifier.verify(verbose: verbose)

        puts
        if result.success
          puts "OK Verification passed (#{format_duration(result.duration)})"
        else
          puts "FAIL Verification failed (exit code: #{result.exit_code})"
          unless result.stderr.strip.empty?
            puts
            puts "Error output:"
            puts result.stderr
          end
          Pim.exit!(1)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Build '#{build_id}' not found")
      end

      private

      def format_duration(seconds)
        if seconds < 60
          "#{seconds.round(1)}s"
        else
          "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
        end
      end
    end
  end
end
```

### 3. Default verification script

Ensure the scaffold template `verifications.d/default.sh` checks the basics:

```bash
#!/bin/bash
set -e

echo "=== PIM Verification ==="

echo "Checking PIM marker file..."
test -f /root/.pim-verified
echo "  OK marker file exists"

echo "Checking SSH service..."
systemctl is-active ssh || systemctl is-active sshd
echo "  OK SSH is running"

echo "Checking qemu-guest-agent..."
if dpkg -l | grep -q qemu-guest-agent; then
  echo "  OK qemu-guest-agent installed"
else
  echo "  SKIP qemu-guest-agent not installed (optional)"
fi

echo "Checking network connectivity..."
ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1 || true
echo "  OK (or skipped in isolated network)"

echo ""
echo "=== All checks passed ==="
```

### 4. Ensure marker file in scaffold

Check that `scripts.d/finalize.sh` in the scaffold template includes:

```bash
# PIM verification marker
touch /root/.pim-verified
```

If not, add it.

### 5. EFI firmware path helper

The `find_efi_firmware` method is duplicated between `LocalBuilder` and `Verifier`. Extract to a shared location:

```ruby
# In Pim::Qemu module or a shared helper
module Pim
  module Qemu
    EFI_FIRMWARE_PATHS = [
      '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
      '/usr/local/share/qemu/edk2-aarch64-code.fd',
      '/usr/share/qemu/edk2-aarch64-code.fd',
      '/usr/share/AAVMF/AAVMF_CODE.fd',
      '/usr/share/qemu-efi-aarch64/QEMU_EFI.fd'
    ].freeze

    EFI_VARS_PATHS = [
      '/opt/homebrew/share/qemu/edk2-arm-vars.fd',
      '/usr/local/share/qemu/edk2-arm-vars.fd',
      '/usr/share/qemu/edk2-arm-vars.fd',
      '/usr/share/AAVMF/AAVMF_VARS.fd'
    ].freeze

    def self.find_efi_firmware
      EFI_FIRMWARE_PATHS.find { |p| File.exist?(p) }
    end

    def self.find_efi_vars_template
      EFI_VARS_PATHS.find { |p| File.exist?(p) }
    end
  end
end
```

Update `LocalBuilder` to use `Pim::Qemu.find_efi_firmware` and `Pim::Qemu.find_efi_vars_template`.

## Test spec

### `spec/pim/verifier_spec.rb` (unit tests)

Mock SSH, mock QEMU, mock Registry:

- Finds image from registry by profile and arch
- Raises `VerifyError` when no image found
- Raises `VerifyError` when image file missing from disk
- Finds verification script for profile
- Falls back to `verifications.d/default.sh`
- Raises `VerifyError` when no verification script found
- Boots VM with `-snapshot` flag
- Uses user-mode networking (port forward)
- Waits for SSH with configured timeout
- Uploads and executes verification script over SSH
- Returns `VerifyResult` with success=true when script exits 0
- Returns `VerifyResult` with success=false when script exits non-zero
- Captures stdout and stderr in result
- Records duration in result
- Shuts down VM after verification (even on failure)
- Cleans up VM on unexpected errors
- Uses correct EFI vars for arm64 images
- Copies EFI vars to temp file (doesn't modify original)
- Cleans up temp EFI vars file

### `spec/pim/commands/verify_spec.rb`

- Takes build_id argument
- Resolves build, profile, arch
- Reports pass with duration
- Reports fail with exit code and stderr
- Exits 1 on failure
- Handles missing build ID

### `spec/integration/build_and_verify_spec.rb` (integration)

**Tagged `integration: true`** — excluded from default runs.

```ruby
RSpec.describe "Build and verify pipeline", integration: true do
  # Requires: QEMU, bsdtar, ISO cached, network for preseed
  # Timeout: 30 minutes
  # Skip if prerequisites missing

  it "builds an image and verifies it" do
    # 1. Create temp project with pim new
    # 2. Add an ISO entry
    # 3. Create a build record
    # 4. pim build run <build_id>
    # 5. pim verify <build_id>
    # 6. Assert result.success == true
  end
end
```

## Verification

```bash
# Unit specs pass
bundle exec rspec spec/pim/verifier_spec.rb
bundle exec rspec spec/pim/commands/verify_spec.rb

# All specs pass
bundle exec rspec

# Manual test (requires QEMU + built image)
cd /path/to/project
pim build run dev-debian        # build first
pim verify dev-debian           # verify
pim verify dev-debian -v        # verbose output

# Confirm image not modified
md5sum ~/.local/share/pim/images/default-arm64-*.qcow2   # before
pim verify dev-debian
md5sum ~/.local/share/pim/images/default-arm64-*.qcow2   # identical

# Integration test
bundle exec rspec --tag integration
```
