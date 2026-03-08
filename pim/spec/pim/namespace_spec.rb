# frozen_string_literal: true

RSpec.describe "Pim namespace" do
  it "has all domain classes at top level" do
    %w[
      Config Server Registry CommandError
      Build Iso Target
      LocalTarget ProxmoxTarget AwsTarget IsoTarget
      FlatRecordSettings BuildManager LocalBuilder
      ArchitectureResolver CacheManager ScriptLoader
      VentoyConfig VentoyManager
      QemuDiskImage QemuCommandBuilder QemuVM
      SSHConnection
      Verifier VerifyResult
    ].each do |klass|
      expect(Pim.const_defined?(klass)).to be(true),
        "Expected Pim::#{klass} to be defined"
    end
  end

  it "has Pim::New::Scaffold for project creation" do
    expect(Pim::New::Scaffold).to be_a(Class)
  end

  it "has Pim::HTTP utility module" do
    expect(Pim.const_defined?(:HTTP)).to be true
    expect(Pim::HTTP).to respond_to(:download)
    expect(Pim::HTTP).to respond_to(:verify_checksum)
    expect(Pim::HTTP).to respond_to(:format_bytes)
  end

  it "has Pim::Qemu utility module" do
    expect(Pim.const_defined?(:Qemu)).to be true
    expect(Pim::Qemu).to respond_to(:find_available_port)
    expect(Pim::Qemu).to respond_to(:check_dependencies)
    expect(Pim::Qemu).to respond_to(:find_efi_firmware)
    expect(Pim::Qemu).to respond_to(:find_efi_vars_template)
    expect(Pim::Qemu.const_defined?(:EFI_FIRMWARE_PATHS)).to be true
    expect(Pim::Qemu.const_defined?(:EFI_VARS_PATHS)).to be true
  end

  it "defines XDG constants on Pim" do
    expect(Pim.const_defined?(:XDG_CONFIG_HOME)).to be true
    expect(Pim.const_defined?(:XDG_DATA_HOME)).to be true
    expect(Pim.const_defined?(:XDG_CACHE_HOME)).to be true
  end

  it "has FlatRecord models" do
    expect(Pim::Profile.superclass).to eq(FlatRecord::Base)
    expect(Pim::Iso.superclass).to eq(FlatRecord::Base)
    expect(Pim::Build.superclass).to eq(FlatRecord::Base)
    expect(Pim::Target.superclass).to eq(FlatRecord::Base)
  end

  it "has Target STI subclasses" do
    expect(Pim::LocalTarget.superclass).to eq(Pim::Target)
    expect(Pim::ProxmoxTarget.superclass).to eq(Pim::Target)
    expect(Pim::AwsTarget.superclass).to eq(Pim::Target)
    expect(Pim::IsoTarget.superclass).to eq(Pim::Target)
  end
end
