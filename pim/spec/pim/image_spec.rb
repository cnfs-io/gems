# frozen_string_literal: true

RSpec.describe Pim::Image do
  let(:data) do
    {
      'id' => 'default-arm64',
      'profile' => 'default',
      'arch' => 'arm64',
      'path' => '/tmp/test-image.qcow2',
      'iso' => 'debian-13-arm64',
      'status' => 'verified',
      'build_time' => Time.now.utc.iso8601,
      'cache_key' => 'abc123',
      'size' => 2_147_483_648,
      'parent_id' => nil,
      'label' => nil,
      'provisioned_with' => nil,
      'provisioned_at' => nil,
      'published_at' => nil,
      'deployments' => []
    }
  end

  subject { described_class.new(data) }

  it "populates all attributes from hash" do
    expect(subject.id).to eq('default-arm64')
    expect(subject.profile).to eq('default')
    expect(subject.arch).to eq('arm64')
    expect(subject.status).to eq('verified')
    expect(subject.cache_key).to eq('abc123')
    expect(subject.deployments).to eq([])
  end

  it "defaults status to 'built' when missing" do
    img = described_class.new({})
    expect(img.status).to eq('built')
  end

  it "defaults deployments to empty array" do
    img = described_class.new({})
    expect(img.deployments).to eq([])
  end

  describe "#golden?" do
    it "returns true when parent_id is nil" do
      expect(subject).to be_golden
    end

    it "returns false when parent_id is present" do
      img = described_class.new(data.merge('parent_id' => 'some-parent'))
      expect(img).not_to be_golden
    end
  end

  describe "#overlay?" do
    it "returns false for golden images" do
      expect(subject).not_to be_overlay
    end

    it "returns true when parent_id present and not published" do
      img = described_class.new(data.merge('parent_id' => 'parent', 'status' => 'provisioned'))
      expect(img).to be_overlay
    end

    it "returns false when published even with parent" do
      img = described_class.new(data.merge('parent_id' => 'parent', 'status' => 'published'))
      expect(img).not_to be_overlay
    end
  end

  describe "#published?" do
    it "returns true when status is published" do
      img = described_class.new(data.merge('status' => 'published'))
      expect(img).to be_published
    end

    it "returns false for other statuses" do
      expect(subject).not_to be_published
    end
  end

  describe "#human_size" do
    it "formats gigabytes" do
      expect(subject.human_size).to eq("2.0G")
    end

    it "formats megabytes" do
      img = described_class.new(data.merge('size' => 52_428_800))
      expect(img.human_size).to eq("50.0M")
    end

    it "formats kilobytes" do
      img = described_class.new(data.merge('size' => 512_000))
      expect(img.human_size).to eq("500.0K")
    end

    it "returns nil when size is nil" do
      img = described_class.new(data.merge('size' => nil))
      expect(img.human_size).to be_nil
    end
  end

  describe "#age" do
    it "returns minutes for recent builds" do
      img = described_class.new(data.merge('build_time' => (Time.now - 300).utc.iso8601))
      expect(img.age).to match(/\d+m ago/)
    end

    it "returns hours for older builds" do
      img = described_class.new(data.merge('build_time' => (Time.now - 7200).utc.iso8601))
      expect(img.age).to match(/\d+h ago/)
    end

    it "returns days for old builds" do
      img = described_class.new(data.merge('build_time' => (Time.now - 172800).utc.iso8601))
      expect(img.age).to match(/\d+d ago/)
    end

    it "returns nil when build_time is nil" do
      img = described_class.new(data.merge('build_time' => nil))
      expect(img.age).to be_nil
    end
  end

  describe "#to_h" do
    it "returns compact hash representation" do
      h = subject.to_h
      expect(h['id']).to eq('default-arm64')
      expect(h['status']).to eq('verified')
      expect(h).not_to have_key('parent_id')  # nil values are compacted
    end
  end
end
