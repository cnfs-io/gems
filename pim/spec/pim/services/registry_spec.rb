# frozen_string_literal: true

RSpec.describe Pim::Registry do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:image_dir) { File.join(tmp_dir, "images") }

  before do
    Pim.reset!
    Pim.configure { |c| c.image_dir = image_dir }
    FileUtils.mkdir_p(image_dir)
  end

  after { FileUtils.remove_entry(tmp_dir) }

  subject { described_class.new(image_dir: image_dir) }

  def create_dummy_image(name)
    path = File.join(image_dir, "#{name}.qcow2")
    File.write(path, "dummy-image-data")
    path
  end

  describe "v1 migration" do
    it "auto-migrates v1 registry to v2 on load" do
      v1_data = {
        'version' => 1,
        'images' => {
          'default-arm64' => {
            'profile' => 'default',
            'arch' => 'arm64',
            'path' => '/tmp/img.qcow2',
            'filename' => 'img.qcow2',
            'iso' => 'debian-13',
            'cache_key' => 'abc',
            'build_time' => '2026-02-25T10:00:00Z',
            'size' => 1234
          }
        }
      }
      File.write(File.join(image_dir, 'registry.yml'), YAML.dump(v1_data))

      reg = described_class.new(image_dir: image_dir)

      # Check via the registry object
      image = reg.find('default-arm64')
      expect(image).to be_a(Pim::Image)
      expect(image.id).to eq('default-arm64')
      expect(image.status).to eq('built')
      expect(image.deployments).to eq([])
      expect(image.profile).to eq('default')
    end
  end

  describe "#register" do
    it "creates entry with status 'built' and no parent" do
      path = create_dummy_image("default-arm64")
      image = subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian-13', cache_key: 'abc123'
      )
      expect(image).to be_a(Pim::Image)
      expect(image.id).to eq('default-arm64')
      expect(image.status).to eq('built')
      expect(image.parent_id).to be_nil
    end
  end

  describe "#register_provisioned" do
    it "creates entry with parent_id, label, script, status provisioned" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian-13', cache_key: 'abc123'
      )

      prov_path = create_dummy_image("default-arm64-k8s")
      image = subject.register_provisioned(
        parent_id: 'default-arm64',
        label: 'k8s',
        path: prov_path,
        script: '/tmp/setup-k8s.sh'
      )

      expect(image.id).to eq('default-arm64-k8s')
      expect(image.status).to eq('provisioned')
      expect(image.parent_id).to eq('default-arm64')
      expect(image.label).to eq('k8s')
      expect(image.provisioned_with).to eq('/tmp/setup-k8s.sh')
      expect(image.provisioned_at).not_to be_nil
    end

    it "raises when parent not found" do
      expect {
        subject.register_provisioned(
          parent_id: 'nonexistent',
          label: 'test',
          path: '/tmp/x.qcow2',
          script: '/tmp/script.sh'
        )
      }.to raise_error(/not found/)
    end
  end

  describe "#find" do
    it "returns Image object for existing id" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian-13', cache_key: 'abc'
      )

      image = subject.find('default-arm64')
      expect(image).to be_a(Pim::Image)
      expect(image.id).to eq('default-arm64')
    end

    it "returns nil for missing id" do
      expect(subject.find('nonexistent')).to be_nil
    end
  end

  describe "#find!" do
    it "raises for missing id" do
      expect { subject.find!('nonexistent') }.to raise_error(/not found/)
    end
  end

  describe "#all" do
    it "returns sorted Image array" do
      path1 = create_dummy_image("a-arm64")
      subject.register(
        profile: 'a', arch: 'arm64', path: path1,
        iso: 'debian', cache_key: 'k1',
        build_time: '2026-02-01T10:00:00Z'
      )

      path2 = create_dummy_image("b-arm64")
      subject.register(
        profile: 'b', arch: 'arm64', path: path2,
        iso: 'debian', cache_key: 'k2',
        build_time: '2026-02-02T10:00:00Z'
      )

      images = subject.all
      expect(images.size).to eq(2)
      expect(images.first.id).to eq('b-arm64')  # newest first
    end
  end

  describe "#update_status" do
    it "transitions status and records published_at" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian', cache_key: 'abc'
      )

      image = subject.update_status('default-arm64', 'published')
      expect(image.status).to eq('published')
      expect(image.published_at).not_to be_nil
    end

    it "returns nil for missing id" do
      expect(subject.update_status('nonexistent', 'published')).to be_nil
    end
  end

  describe "#record_deployment" do
    it "appends to deployments array" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian', cache_key: 'abc'
      )

      dep = subject.record_deployment(
        'default-arm64',
        target: 'proxmox-sg',
        target_type: 'proxmox',
        metadata: { 'vm_id' => '9000' }
      )

      expect(dep['target']).to eq('proxmox-sg')
      expect(dep['vm_id']).to eq('9000')

      image = subject.find('default-arm64')
      expect(image.deployments.size).to eq(1)
    end
  end

  describe "#delete" do
    it "removes entry and returns Image" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian', cache_key: 'abc'
      )

      image = subject.delete('default-arm64')
      expect(image).to be_a(Pim::Image)
      expect(subject.find('default-arm64')).to be_nil
    end

    it "returns nil for missing id" do
      expect(subject.delete('nonexistent')).to be_nil
    end
  end

  describe "#cached?" do
    it "returns true for matching cache key with existing file" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian', cache_key: 'abc'
      )

      expect(subject.cached?(profile: 'default', arch: 'arm64', cache_key: 'abc')).to be true
    end

    it "returns false for non-matching cache key" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian', cache_key: 'abc'
      )

      expect(subject.cached?(profile: 'default', arch: 'arm64', cache_key: 'xyz')).to be false
    end
  end

  describe "#find_legacy" do
    it "returns raw hash for backward compat" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian', cache_key: 'abc'
      )

      entry = subject.find_legacy(profile: 'default', arch: 'arm64')
      expect(entry).to be_a(Hash)
      expect(entry['id']).to eq('default-arm64')
    end
  end

  describe "#clean_orphaned" do
    it "removes entries with missing files" do
      path = create_dummy_image("default-arm64")
      subject.register(
        profile: 'default', arch: 'arm64', path: path,
        iso: 'debian', cache_key: 'abc'
      )

      FileUtils.rm(path)

      removed = subject.clean_orphaned
      expect(removed).to eq(['default-arm64'])
      expect(subject.find('default-arm64')).to be_nil
    end
  end
end
