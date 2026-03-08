# frozen_string_literal: true

RSpec.describe Pim::Verifier do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:image_dir) { File.join(tmp_dir, "images") }
  let(:image_path) { File.join(image_dir, "default-arm64-20260220.qcow2") }

  let(:profile) do
    instance_double(Pim::Profile,
      id: "default",
      resolve: "changeme",
      verification_script: File.join(tmp_dir, "resources", "verifications", "default.sh"))
  end

  let(:build) do
    instance_double(Pim::Build,
      id: "dev-debian",
      resolved_profile: profile,
      arch: "arm64",
      memory: 2048,
      cpus: 2,
      ssh_user: "ansible",
      ssh_timeout: 300)
  end

  let(:registry) do
    instance_double(Pim::Registry)
  end

  let(:vm) do
    instance_double(Pim::QemuVM,
      pid: 12345,
      ssh_port: 2222,
      running?: true)
  end

  let(:ssh) do
    instance_double(Pim::SSHConnection)
  end

  let(:builder) do
    instance_double(Pim::QemuCommandBuilder)
  end

  subject { described_class.new(build: build) }

  before do
    Pim.reset!
    Pim.configure do |c|
      c.image_dir = image_dir
    end

    FileUtils.mkdir_p(image_dir)
    FileUtils.mkdir_p(File.join(tmp_dir, "resources", "verifications"))
    File.write(File.join(tmp_dir, "resources", "verifications", "default.sh"), "#!/bin/bash\nexit 0")

    # Stub Registry
    allow(Pim::Registry).to receive(:new).and_return(registry)
    allow(registry).to receive(:find_legacy).and_return({
      'profile' => 'default',
      'arch' => 'arm64',
      'path' => image_path
    })

    # Create fake image file
    File.write(image_path, "fake-image")

    # Stub QEMU
    allow(Pim::Qemu).to receive(:find_available_port).and_return(2222)
    allow(Pim::Qemu).to receive(:find_efi_firmware).and_return(nil)
    allow(Pim::QemuCommandBuilder).to receive(:new).and_return(builder)
    allow(builder).to receive(:add_drive).and_return(builder)
    allow(builder).to receive(:add_user_net).and_return(builder)
    allow(builder).to receive(:extra_args).and_return(builder)
    allow(builder).to receive(:build).and_return(["qemu-system-aarch64"])
    allow(Pim::QemuVM).to receive(:new).and_return(vm)
    allow(vm).to receive(:start_background).and_return(vm)
    allow(vm).to receive(:wait_for_ssh).and_return(true)
    allow(vm).to receive(:shutdown)
    allow(vm).to receive(:kill)

    # Stub SSH
    allow(Pim::SSHConnection).to receive(:new).and_return(ssh)
    allow(ssh).to receive(:upload)
    allow(ssh).to receive(:execute).and_return({ stdout: "OK", stderr: "", exit_code: 0 })

    # Suppress output
    allow(subject).to receive(:puts)
    allow(subject).to receive(:sleep)
  end

  after { FileUtils.remove_entry(tmp_dir) }

  describe "#verify" do
    it "returns VerifyResult with success=true when script exits 0" do
      result = subject.verify
      expect(result).to be_a(Pim::VerifyResult)
      expect(result.success).to be true
      expect(result.exit_code).to eq(0)
    end

    it "returns VerifyResult with success=false when script exits non-zero" do
      allow(ssh).to receive(:execute)
        .with("/tmp/pim-verify.sh", sudo: true)
        .and_return({ stdout: "", stderr: "check failed", exit_code: 1 })

      result = subject.verify
      expect(result.success).to be false
      expect(result.exit_code).to eq(1)
    end

    it "captures stdout and stderr in result" do
      allow(ssh).to receive(:execute)
        .with("/tmp/pim-verify.sh", sudo: true)
        .and_return({ stdout: "all good", stderr: "warn: foo", exit_code: 0 })

      result = subject.verify
      expect(result.stdout).to eq("all good")
      expect(result.stderr).to eq("warn: foo")
    end

    it "records duration in result" do
      result = subject.verify
      expect(result.duration).to be_a(Float).or be_a(Integer)
      expect(result.duration).to be >= 0
    end

    it "finds image from registry by profile and arch" do
      expect(Pim::Registry).to receive(:new).with(image_dir: image_dir).and_return(registry)
      expect(registry).to receive(:find_legacy).with(profile: "default", arch: "arm64")
      subject.verify
    end

    it "returns failure when no image found in registry" do
      allow(registry).to receive(:find_legacy).and_return(nil)
      result = subject.verify
      expect(result.success).to be false
      expect(result.stderr).to include("No image found")
    end

    it "returns failure when image file missing from disk" do
      File.delete(image_path)
      result = subject.verify
      expect(result.success).to be false
      expect(result.stderr).to include("Image file missing")
    end

    it "finds verification script for profile" do
      expect(profile).to receive(:verification_script).and_return(
        File.join(tmp_dir, "resources/verifications", "default.sh")
      )
      subject.verify
    end

    it "returns failure when no verification script found" do
      allow(profile).to receive(:verification_script).and_return(nil)
      result = subject.verify
      expect(result.success).to be false
      expect(result.stderr).to include("No verification script")
    end

    it "boots VM with -snapshot flag" do
      expect(builder).to receive(:extra_args).with('-snapshot').and_return(builder)
      subject.verify
    end

    it "uses user-mode networking with port forwarding" do
      expect(builder).to receive(:add_user_net).with(host_port: 2222, guest_port: 22).and_return(builder)
      subject.verify
    end

    it "waits for SSH with configured timeout" do
      expect(vm).to receive(:wait_for_ssh).with(timeout: 300, poll_interval: 5).and_return(true)
      subject.verify
    end

    it "returns failure on SSH timeout" do
      allow(vm).to receive(:wait_for_ssh).and_return(false)
      result = subject.verify
      expect(result.success).to be false
      expect(result.stderr).to include("Timed out waiting for SSH")
    end

    it "uploads and executes verification script over SSH" do
      script_path = File.join(tmp_dir, "resources/verifications", "default.sh")
      expect(ssh).to receive(:upload).with(script_path, "/tmp/pim-verify.sh")
      expect(ssh).to receive(:execute).with("chmod +x /tmp/pim-verify.sh", sudo: true)
      expect(ssh).to receive(:execute).with("/tmp/pim-verify.sh", sudo: true)
        .and_return({ stdout: "OK", stderr: "", exit_code: 0 })
      subject.verify
    end

    it "shuts down VM after verification" do
      expect(vm).to receive(:shutdown).with(timeout: 30)
      subject.verify
    end

    it "cleans up VM on unexpected errors" do
      allow(vm).to receive(:wait_for_ssh).and_raise(StandardError, "boom")
      expect(vm).to receive(:kill)
      subject.verify
    end

    context "verbose mode" do
      it "prints stdout when verbose" do
        allow(ssh).to receive(:execute)
          .with("/tmp/pim-verify.sh", sudo: true)
          .and_return({ stdout: "verbose output", stderr: "", exit_code: 0 })

        expect(subject).to receive(:puts).with("verbose output")
        subject.verify(verbose: true)
      end
    end
  end

  describe "arm64 EFI handling" do
    let(:efi_code_path) { File.join(tmp_dir, "edk2-aarch64-code.fd") }
    let(:efi_vars_path) { image_path.sub(/\.qcow2$/, '-efivars.fd') }

    before do
      File.write(efi_code_path, "efi-code")
      File.write(efi_vars_path, "efi-vars")
      allow(Pim::Qemu).to receive(:find_efi_firmware).and_return(efi_code_path)
    end

    it "uses EFI vars for arm64 images" do
      expect(builder).to receive(:extra_args).with(
        '-drive', "if=pflash,format=raw,file=#{efi_code_path},readonly=on",
        '-drive', "if=pflash,format=raw,file=#{efi_vars_path}.verify-tmp"
      ).and_return(builder)

      subject.verify
    end

    it "copies EFI vars to temp file" do
      subject.verify
      expect(File.exist?("#{efi_vars_path}.verify-tmp")).to be false  # cleaned up after
    end

    it "cleans up temp EFI vars file after verification" do
      allow(FileUtils).to receive(:cp).and_call_original
      expect(FileUtils).to receive(:rm_f).with("#{efi_vars_path}.verify-tmp").at_least(:once)
      subject.verify
    end
  end

  describe "x86_64 builds" do
    let(:build) do
      instance_double(Pim::Build,
        id: "dev-debian",
        resolved_profile: profile,
        arch: "x86_64",
        memory: 2048,
        cpus: 2,
        ssh_user: "ansible",
        ssh_timeout: 300)
    end

    it "does not add EFI pflash args" do
      expect(builder).not_to receive(:extra_args).with(
        '-drive', anything,
        '-drive', anything
      )
      subject.verify
    end
  end
end
