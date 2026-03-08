---
---

# Plan 03 — E2E Build and Verify

## Context

Read before starting:
- `spec/integration/build_and_verify_spec.rb` (existing stub)
- `spec/support/test_project.rb` (from plan-02)
- `lib/pim/build/manager.rb`
- `lib/pim/services/verifier.rb`
- `lib/pim/services/qemu.rb`
- `lib/pim/services/architecture_resolver.rb`
- `lib/pim/models/iso.rb` (download/verify methods)
- `resources/verifications/default.sh` (in template directory)
- `docs/collection-layout/plan-02-fixture-strategy.md` (must be complete first)

## Depends On

Plan 02 (fixture-strategy) must be complete. This plan uses `TestProject` helper.

## Problem

PIM has no end-to-end test that proves the core deliverable works: download an ISO, build a VM image, and verify it boots and passes checks. The existing `spec/integration/build_and_verify_spec.rb` is a stub with a `skip` inside it and references stale build IDs.

## Design Decisions

### Tag: `e2e` (not `integration`)

Use a dedicated `e2e` tag to distinguish from lighter integration tests. This test downloads ~750MB, runs QEMU for 10-30 minutes, and requires real system dependencies.

```bash
bundle exec rspec --tag e2e    # run E2E only
bundle exec rspec               # skips E2E (and integration)
```

### Architecture-aware ISO selection

The spec detects the host architecture and selects the matching ISO from the scaffold defaults:
- `x86_64` / `amd64` host → `debian-13-amd64`
- `aarch64` / `arm64` host → `debian-13-arm64`

If the host arch doesn't match either, the spec skips.

### Real ISO download, real XDG cache

The ISO is downloaded to `~/.cache/pim/isos/` (the real XDG cache location). This means:
- First run downloads ~750MB (one-time cost)
- Subsequent runs find the cached ISO and skip download
- No mocking of HTTP, checksums, or filesystem

### Real build output, real image dir

The built qcow2 image goes to `~/.local/share/pim/images/` (real XDG data location). The registry entry is real. After the test, the image can be cleaned up or left for manual inspection.

### Configurable timeout

The build timeout is controlled by `PIM_E2E_TIMEOUT` env var (default: 1800 seconds / 30 minutes). The preseed install is the slow part — it depends on network speed and host performance.

### Skip conditions

Skip the entire spec if:
1. QEMU is not installed (checks `qemu-system-{arch}` and `qemu-img`)
2. `bsdtar` is not installed (needed for ISO kernel extraction)
3. Host architecture is not amd64 or arm64
4. `PIM_SKIP_E2E=1` is set (escape hatch for CI)

### Cleanup strategy

The spec creates a scaffold project in a tmpdir (cleaned up after). The built image is **not** automatically deleted — it persists in `~/.local/share/pim/images/`. Rationale:
- Rebuilds take 10-30 minutes; keeping the image avoids re-running on next test
- `pim build clean` can be used to manually remove it
- The cache key mechanism means the image is reusable

If you want the spec to clean up the image, set `PIM_E2E_CLEANUP=1`.

## Implementation Spec

### 1. Update `spec/spec_helper.rb`

Add the `e2e` tag exclusion alongside the existing `integration` exclusion:

```ruby
RSpec.configure do |config|
  config.filter_run_excluding integration: true
  config.filter_run_excluding e2e: true
  # ...
end
```

### 2. Rewrite `spec/integration/build_and_verify_spec.rb`

Replace the existing stub with a working E2E spec:

```ruby
# frozen_string_literal: true

RSpec.describe "E2E: Build and verify pipeline", e2e: true do
  # Full end-to-end test: scaffold → download ISO → build VM → verify
  #
  # Prerequisites:
  #   - qemu-system-{x86_64,aarch64} and qemu-img installed
  #   - bsdtar installed (for ISO kernel extraction)
  #   - Network access (ISO download + preseed)
  #   - ~750MB disk for ISO cache (one-time)
  #   - ~20GB disk for build image
  #   - 10-30 minutes runtime
  #
  # Run with:
  #   bundle exec rspec --tag e2e
  #
  # Environment variables:
  #   PIM_E2E_TIMEOUT=1800   Build timeout in seconds (default: 1800)
  #   PIM_E2E_CLEANUP=1      Delete built image after test
  #   PIM_SKIP_E2E=1         Skip E2E tests entirely

  let(:project_dir) { TestProject.create(name: "e2e-test") }
  let(:resolver) { Pim::ArchitectureResolver.new }
  let(:timeout) { Integer(ENV.fetch("PIM_E2E_TIMEOUT", "1800")) }

  before(:all) do
    skip "PIM_SKIP_E2E is set" if ENV["PIM_SKIP_E2E"]

    # Check QEMU
    missing = Pim::Qemu.check_dependencies
    skip "QEMU not installed (missing: #{missing.join(', ')})" if missing.any?

    # Check bsdtar
    _, status = Open3.capture2("which bsdtar")
    skip "bsdtar not installed" unless status.success?
  end

  after do
    if ENV["PIM_E2E_CLEANUP"] && @built_image_path
      FileUtils.rm_f(@built_image_path)
      # Also clean registry entry
      registry = Pim::Registry.new(image_dir: Pim.config.image_dir)
      registry.remove(profile: @build.resolved_profile.id, arch: @build.arch) rescue nil
    end

    TestProject.cleanup(project_dir)
  end

  def host_iso_id
    arch = resolver.host_arch
    case arch
    when "x86_64" then "debian-13-amd64"
    when "arm64"  then "debian-13-arm64"
    else skip "Unsupported host architecture for E2E: #{arch}"
    end
  end

  def host_build_id
    # The scaffold default build uses debian-13-amd64.
    # If we're on arm64, we need to create a build pointing at the arm64 ISO.
    if resolver.host_arch == "arm64"
      TestProject.append_records(project_dir, "builds", [
        { "id" => "default-arm64", "profile" => "default", "iso" => "debian-13-arm64",
          "target" => "local", "distro" => "debian" }
      ])
      "default-arm64"
    else
      "default"
    end
  end

  it "downloads ISO, builds image, and verifies it" do
    # 1. Boot project
    TestProject.boot(project_dir)

    # 2. Resolve ISO for host arch
    iso_id = host_iso_id
    iso = Pim::Iso.find(iso_id)

    # 3. Download ISO (uses real cache, skips if already downloaded)
    unless iso.downloaded?
      puts "\n  Downloading #{iso.name} (~750MB, one-time)..."
      iso.download
    end
    expect(iso.downloaded?).to be true

    # 4. Resolve build for host arch
    build_id = host_build_id
    # Re-boot to pick up any appended records
    Pim.reset!
    TestProject.boot(project_dir)
    @build = Pim::Build.find(build_id)

    puts "\n  Build: #{@build.id}"
    puts "  Profile: #{@build.profile}"
    puts "  ISO: #{@build.iso}"
    puts "  Arch: #{@build.arch}"
    puts "  Timeout: #{timeout}s"

    # 5. Run build
    manager = Pim::BuildManager.new
    result_path = manager.execute_build(@build)
    @built_image_path = result_path

    expect(result_path).to be_a(String)
    expect(File.exist?(result_path)).to be true
    puts "  Image: #{result_path}"

    # 6. Verify
    puts "  Running verification..."
    verifier = Pim::Verifier.new(build: @build)
    result = verifier.verify(verbose: true)

    puts "  Duration: #{result.duration.round(1)}s"
    puts "  Exit code: #{result.exit_code}"

    expect(result.success).to be true
    expect(result.exit_code).to eq(0)
  end
end
```

### 3. Key implementation notes

**ISO download with checksum_url**: The scaffold ISOs use `checksum_url` instead of inline `checksum`. Verify that `Pim::Iso#download` and `Pim::Iso#verify` support `checksum_url` — if the ISO model currently only handles inline `checksum`, this needs a small enhancement:

- Download the SHA256SUMS file from `checksum_url`
- Parse it to find the line matching `filename`
- Extract the sha256 hash
- Use it for verification

Check `lib/pim/models/iso.rb` — if `verify` only uses the `checksum` attribute, add a `resolved_checksum` method that:
1. Returns `checksum` if present
2. Otherwise downloads and parses `checksum_url` to find the checksum for `filename`

This is a small but critical piece — without it, the E2E test can't verify the ISO.

**Build manager return value**: The E2E spec expects `execute_build` to return the image path string. Verify `BuildManager#execute_build` returns this. If it currently returns `nil` or prints to stdout, adjust accordingly.

**Registry lookup**: The verifier uses `Pim::Registry` to find the built image. The build manager should register the image after building. Verify this chain works end-to-end.

## Test Spec

The E2E spec IS the test. It's self-verifying:

1. ISO downloads successfully and checksum matches
2. Build completes without error and produces a qcow2 file
3. Verification boots the image, runs the verification script, and gets exit code 0

### Negative path (optional, low priority)

A spec that builds with a deliberately broken preseed or missing script — verifying that failures are reported correctly. This is nice-to-have, not required for this plan.

## Verification

```bash
# Run E2E test
bundle exec rspec --tag e2e

# Should see output like:
#   Downloading Debian 13.3.0 amd64 netinst (~750MB, one-time)...
#   Build: default
#   Profile: default
#   ISO: debian-13-amd64
#   Arch: x86_64
#   Timeout: 1800s
#   Image: /Users/roberto/.local/share/pim/images/default-x86_64-abc123.qcow2
#   Running verification...
#   Duration: 847.3s
#   Exit code: 0
#   1 example, 0 failures

# Regular specs still work and skip E2E
bundle exec rspec
```

Also verify the unit test suite is unaffected:

```bash
bundle exec rspec --exclude-pattern "spec/integration/**/*"
```
