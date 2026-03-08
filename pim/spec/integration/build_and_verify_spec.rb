# frozen_string_literal: true

require "open3"
require "tempfile"

RSpec.describe "E2E: Build and verify pipeline", e2e: true do
  # Full end-to-end test: scaffold -> download ISO -> build VM -> verify
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
  #   PIM_E2E_TIMEOUT=1800       Build timeout in seconds (default: 1800)
  #   PIM_E2E_VERIFY_TIMEOUT=300 Verify SSH timeout in seconds (default: 300)
  #   PIM_E2E_CLEANUP=1          Delete built image after test
  #   PIM_SKIP_E2E=1             Skip E2E tests entirely

  let(:project_dir) { TestProject.create(name: "e2e-test") }
  let(:resolver) { Pim::ArchitectureResolver.new }
  let(:timeout) { Integer(ENV.fetch("PIM_E2E_TIMEOUT", "1800")) }
  let(:verify_timeout) { Integer(ENV.fetch("PIM_E2E_VERIFY_TIMEOUT", "300")) }
  let(:console_log) { Tempfile.new(["pim-verify-console-", ".log"]) }

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
      registry = Pim::Registry.new(image_dir: Pim.config.image_dir)
      registry.remove(profile: @build.resolved_profile.id, arch: @build.arch) rescue nil
    end

    console_log.close
    console_log.unlink
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
    # The scaffold includes both default (amd64) and default-arm64 builds.
    if resolver.host_arch == "arm64"
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
    @build = Pim::Build.find(host_build_id)

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

    # 6. Verify (with console log for debugging)
    puts "  Running verification..."
    puts "  Console log: #{console_log.path}"
    verifier = Pim::Verifier.new(build: @build)
    result = verifier.verify(
      verbose: true,
      console_log: console_log.path,
      ssh_timeout: verify_timeout
    )

    puts "  Duration: #{result.duration.round(1)}s"
    puts "  Exit code: #{result.exit_code}"

    # Dump console log on failure for debugging
    unless result.success
      puts "\n  === CONSOLE LOG (last 100 lines) ==="
      lines = File.readlines(console_log.path) rescue []
      lines.last(100).each { |line| puts "  #{line}" }
      puts "  === END CONSOLE LOG ==="
      puts "  Full log: #{console_log.path}"
    end

    expect(result.success).to be(true), "Verification failed: #{result.stderr}"
    expect(result.exit_code).to eq(0)
  end
end
