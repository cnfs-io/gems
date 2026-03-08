# frozen_string_literal: true

RSpec.describe Pim::ImageCommand do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:image_dir) { File.join(tmp_dir, "images") }
  let(:registry) { instance_double(Pim::Registry) }

  before do
    Pim.reset!
    Pim.configure { |c| c.image_dir = image_dir }
    FileUtils.mkdir_p(image_dir)
    allow(Pim::Registry).to receive(:new).and_return(registry)
  end

  after { FileUtils.remove_entry(tmp_dir) }

  def capture_output
    stdout = StringIO.new
    $stdout = stdout
    yield
    stdout.string
  ensure
    $stdout = STDOUT
  end

  let(:golden_image) do
    Pim::Image.new(
      'id' => 'default-arm64',
      'profile' => 'default',
      'arch' => 'arm64',
      'path' => File.join(image_dir, 'default-arm64.qcow2'),
      'status' => 'verified',
      'build_time' => '2026-02-25T10:00:00Z',
      'size' => 2_147_483_648,
      'parent_id' => nil,
      'label' => nil,
      'deployments' => []
    )
  end

  let(:provisioned_image) do
    Pim::Image.new(
      'id' => 'default-arm64-k8s',
      'profile' => 'default',
      'arch' => 'arm64',
      'path' => File.join(image_dir, 'default-arm64-k8s.qcow2'),
      'status' => 'provisioned',
      'build_time' => '2026-02-25T10:00:00Z',
      'size' => 3_000_000_000,
      'parent_id' => 'default-arm64',
      'label' => 'k8s',
      'provisioned_with' => '/tmp/setup-k8s.sh',
      'provisioned_at' => '2026-02-25T11:00:00Z',
      'deployments' => []
    )
  end

  describe Pim::ImageCommand::List do
    it "lists all images" do
      allow(registry).to receive(:all).and_return([golden_image, provisioned_image])
      output = capture_output { subject.call }
      expect(output).to include('default-arm64')
      expect(output).to include('verified')
      expect(output).to include('k8s')
    end

    it "shows message when no images" do
      allow(registry).to receive(:all).and_return([])
      output = capture_output { subject.call }
      expect(output).to include('No images found')
    end

    it "filters by status" do
      allow(registry).to receive(:all).and_return([golden_image, provisioned_image])
      output = capture_output { subject.call(status: 'provisioned') }
      expect(output).to include('k8s')
      expect(output).not_to include('verified')
    end
  end

  describe Pim::ImageCommand::Show do
    it "shows full image detail" do
      allow(registry).to receive(:find).with('default-arm64').and_return(golden_image)
      output = capture_output { subject.call(id: 'default-arm64') }
      expect(output).to include('default-arm64')
      expect(output).to include('verified')
      expect(output).to include('arm64')
    end

    it "shows lineage for provisioned images" do
      allow(registry).to receive(:find).with('default-arm64-k8s').and_return(provisioned_image)
      output = capture_output { subject.call(id: 'default-arm64-k8s') }
      expect(output).to include('Lineage')
      expect(output).to include('default-arm64')
      expect(output).to include('setup-k8s.sh')
    end

    it "errors for unknown id" do
      allow(registry).to receive(:find).with('nonexistent').and_return(nil)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(id: 'nonexistent') }.to output(/not found/).to_stderr
    end
  end

  describe Pim::ImageCommand::Delete do
    it "warns about children and exits" do
      allow(registry).to receive(:find).with('default-arm64').and_return(golden_image)
      allow(registry).to receive(:all).and_return([golden_image, provisioned_image])

      Pim.console_mode!
      output = capture_output do
        expect { subject.call(id: 'default-arm64') }.to raise_error(Pim::CommandError)
      end
      expect(output).to include('depend on this image')
    end

    it "deletes with --force skipping confirmation" do
      img_path = File.join(image_dir, 'default-arm64.qcow2')
      File.write(img_path, "data")
      allow(registry).to receive(:find).with('default-arm64').and_return(golden_image)
      allow(registry).to receive(:all).and_return([golden_image])
      allow(registry).to receive(:delete).with('default-arm64')

      output = capture_output { subject.call(id: 'default-arm64', force: true) }
      expect(output).to include("Removed 'default-arm64' from registry")
    end

    it "keeps file with --keep-file" do
      img_path = File.join(image_dir, 'default-arm64.qcow2')
      File.write(img_path, "data")
      allow(registry).to receive(:find).with('default-arm64').and_return(golden_image)
      allow(registry).to receive(:all).and_return([golden_image])
      allow(registry).to receive(:delete).with('default-arm64')

      output = capture_output { subject.call(id: 'default-arm64', force: true, keep_file: true) }
      expect(File.exist?(img_path)).to be true
      expect(output).to include("Removed 'default-arm64' from registry")
    end
  end

  describe Pim::ImageCommand::Publish do
    let(:disk) { instance_double(Pim::QemuDiskImage) }

    it "publishes a standalone golden image (status transition only)" do
      img_path = File.join(image_dir, 'default-arm64.qcow2')
      File.write(img_path, "data")

      standalone_image = Pim::Image.new(
        golden_image.to_h.merge('path' => img_path, 'status' => 'verified')
      )
      allow(registry).to receive(:find).with('default-arm64').and_return(standalone_image)
      allow(Pim::QemuDiskImage).to receive(:new).and_return(disk)
      allow(disk).to receive(:info).and_return({ 'format' => 'qcow2' })
      allow(registry).to receive(:update_status).and_return(standalone_image)

      output = capture_output { subject.call(id: 'default-arm64') }
      expect(output).to include('already standalone')
      expect(registry).to have_received(:update_status).with('default-arm64', 'published')
    end

    it "is a no-op for already published images" do
      published = Pim::Image.new(golden_image.to_h.merge('status' => 'published'))
      allow(registry).to receive(:find).with('default-arm64').and_return(published)

      img_path = File.join(image_dir, 'default-arm64.qcow2')
      File.write(img_path, "data")

      output = capture_output { subject.call(id: 'default-arm64') }
      expect(output).to include('already published')
    end

    it "errors for missing image" do
      allow(registry).to receive(:find).with('nonexistent').and_return(nil)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(id: 'nonexistent') }.to output(/not found/).to_stderr
    end
  end

  describe Pim::ImageCommand::Deploy do
    let(:published_image) do
      Pim::Image.new(
        'id' => 'default-arm64',
        'profile' => 'default',
        'arch' => 'arm64',
        'path' => File.join(image_dir, 'default-arm64.qcow2'),
        'status' => 'published',
        'build_time' => '2026-02-25T10:00:00Z',
        'size' => 2_147_483_648,
        'deployments' => []
      )
    end

    let(:target) do
      double('ProxmoxTarget',
             class: Pim::ProxmoxTarget,
             type: 'proxmox',
             host: 'pve1.local',
             node: 'pve1',
             storage: 'local-lvm',
             bridge: 'vmbr0',
             vm_id_start: 9000,
             ssh_key: nil)
    end

    it "errors for unknown image" do
      allow(registry).to receive(:find).with('nonexistent').and_return(nil)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(image_id: 'nonexistent', target_id: 'pve1') }.to output(/not found/).to_stderr
    end

    it "errors for unknown target" do
      allow(registry).to receive(:find).with('default-arm64').and_return(published_image)
      allow(Pim::Target).to receive(:find).with('nonexistent').and_raise(
        FlatRecord::RecordNotFound.new("Target with id 'nonexistent' not found")
      )
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(image_id: 'default-arm64', target_id: 'nonexistent') }.to output(/not found/).to_stderr
    end

    it "deploys with dry_run" do
      File.write(File.join(image_dir, 'default-arm64.qcow2'), "data")
      allow(registry).to receive(:find).with('default-arm64').and_return(published_image)
      allow(Pim::Target).to receive(:find).with('pve1').and_return(target)
      allow(Pim::Build).to receive(:find).and_raise(FlatRecord::RecordNotFound)
      allow(target).to receive(:deploy).and_return({ vm_id: 9000, name: 'pim-default-arm64', dry_run: true })

      output = capture_output { subject.call(image_id: 'default-arm64', target_id: 'pve1', dry_run: true) }
      expect(output).to include("Deploying")
    end

    it "errors for unpublished overlay without auto_publish" do
      Pim.configure { |c| c.images { |i| i.auto_publish = false } }
      overlay = Pim::Image.new(
        'id' => 'default-arm64-k8s',
        'profile' => 'default',
        'arch' => 'arm64',
        'path' => File.join(image_dir, 'default-arm64-k8s.qcow2'),
        'status' => 'provisioned',
        'parent_id' => 'default-arm64',
        'label' => 'k8s',
        'deployments' => []
      )
      allow(registry).to receive(:find).with('default-arm64-k8s').and_return(overlay)
      allow(Pim::Target).to receive(:find).with('pve1').and_return(target)
      Pim.instance_variable_set(:@console_mode, false)
      expect(Kernel).to receive(:exit).with(1)
      expect { subject.call(image_id: 'default-arm64-k8s', target_id: 'pve1') }.to output(/must be published/).to_stderr
    end
  end

  it "inherits from RestCli::Command" do
    expect(described_class.superclass).to eq(RestCli::Command)
  end
end
