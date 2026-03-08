# frozen_string_literal: true

require "pim/services/deployers/proxmox_deployer"

RSpec.describe Pim::ProxmoxDeployer do
  let(:image_path) { File.join(Dir.mktmpdir, "test.qcow2") }
  let(:image) do
    Pim::Image.new(
      'id' => 'default-arm64',
      'profile' => 'default',
      'arch' => 'arm64',
      'path' => image_path,
      'status' => 'published',
      'build_time' => '2026-02-25T10:00:00Z',
      'size' => 2_147_483_648,
      'label' => 'k8s',
      'deployments' => []
    )
  end

  let(:target) do
    double('ProxmoxTarget',
           host: 'pve1.local',
           node: 'pve1',
           storage: 'local-lvm',
           bridge: 'vmbr0',
           vm_id_start: 9000,
           ssh_key: nil)
  end

  let(:ssh) { instance_double(Pim::SSHConnection) }

  before do
    File.write(image_path, "fake-qcow2")
  end

  after { FileUtils.rm_rf(File.dirname(image_path)) }

  subject { described_class.new(target: target, image: image) }

  describe "#deploy with dry_run" do
    it "prints steps without executing" do
      output = StringIO.new
      $stdout = output
      result = subject.deploy(dry_run: true)
      $stdout = STDOUT

      expect(result[:dry_run]).to be true
      expect(result[:vm_id]).to eq(9000)
      expect(result[:name]).to eq("pim-default-k8s")
      expect(output.string).to include("Dry run")
      expect(output.string).to include("qm create")
    end
  end

  describe "validation" do
    it "raises for missing image file" do
      FileUtils.rm_f(image_path)
      expect { subject.deploy }.to raise_error(described_class::Error, /Image file missing/)
    end

    it "raises for unpublished overlay" do
      overlay = Pim::Image.new(
        image.to_h.merge('status' => 'provisioned', 'parent_id' => 'some-parent')
      )
      deployer = described_class.new(target: target, image: overlay)
      expect { deployer.deploy }.to raise_error(described_class::Error, /must be published/)
    end

    it "allows golden images (no parent)" do
      golden = Pim::Image.new(
        image.to_h.merge('status' => 'verified', 'parent_id' => nil)
      )
      deployer = described_class.new(target: target, image: golden)
      # Should pass validation and fail on SSH connect (expected)
      expect { deployer.deploy }.to raise_error(StandardError)
    end

    it "raises for missing target host" do
      allow(target).to receive(:host).and_return(nil)
      expect { subject.deploy }.to raise_error(described_class::Error, /Target host/)
    end

    it "raises for missing target node" do
      allow(target).to receive(:node).and_return(nil)
      expect { subject.deploy }.to raise_error(described_class::Error, /Target node/)
    end
  end

  describe "#template_name" do
    it "uses label when present" do
      result = subject.deploy(dry_run: true)
      expect(result[:name]).to eq("pim-default-k8s")
    end

    it "falls back to image id without label" do
      no_label = Pim::Image.new(image.to_h.merge('label' => nil))
      deployer = described_class.new(target: target, image: no_label)
      result = deployer.deploy(dry_run: true)
      expect(result[:name]).to eq("pim-default-arm64")
    end
  end

  describe "#parse_disk_ref" do
    it "extracts disk path from qm importdisk output" do
      output = "transferred 2.0 GiB of 10.0 GiB\nSuccessfully imported disk as 'local-lvm:vm-9000-disk-0'"
      result = subject.send(:parse_disk_ref, output, 9000, 'local-lvm')
      expect(result).to eq("local-lvm:vm-9000-disk-0")
    end

    it "falls back to constructed path" do
      result = subject.send(:parse_disk_ref, "some other output", 9000, 'local-lvm')
      expect(result).to eq("local-lvm:vm-9000-disk-0")
    end
  end

  describe "build defaults" do
    it "uses build memory and cpus when provided" do
      build = double('Build', memory: 4096, cpus: 4)
      deployer = described_class.new(target: target, image: image, build: build)
      result = deployer.deploy(dry_run: true)

      output = StringIO.new
      $stdout = output
      result = deployer.deploy(dry_run: true)
      $stdout = STDOUT

      expect(output.string).to include("--memory 4096")
      expect(output.string).to include("--cores 4")
    end

    it "falls back to defaults without build" do
      output = StringIO.new
      $stdout = output
      subject.deploy(dry_run: true)
      $stdout = STDOUT

      expect(output.string).to include("--memory 2048")
      expect(output.string).to include("--cores 2")
    end
  end
end
