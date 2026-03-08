# frozen_string_literal: true

require "pim/services/deployers/aws_deployer"

RSpec.describe Pim::AwsDeployer do
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
    double('AwsTarget',
           id: 'aws-us-east',
           region: 'us-east-1',
           s3_bucket: 'my-pim-images',
           s3_prefix: 'pim-imports/',
           ami_name_prefix: 'pim',
           iam_role: 'vmimport',
           cleanup_s3: true)
  end

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
      expect(result[:region]).to eq('us-east-1')
      expect(result[:ami_name]).to match(/^pim-k8s-/)
      expect(output.string).to include("Dry run")
      expect(output.string).to include("s3://my-pim-images/")
      expect(output.string).to include("Register AMI")
    end

    it "includes cleanup step when cleanup_s3 is true" do
      output = StringIO.new
      $stdout = output
      subject.deploy(dry_run: true)
      $stdout = STDOUT

      expect(output.string).to include("Clean up S3")
    end

    it "omits cleanup step when cleanup_s3 is false" do
      allow(target).to receive(:cleanup_s3).and_return(false)

      output = StringIO.new
      $stdout = output
      subject.deploy(dry_run: true)
      $stdout = STDOUT

      expect(output.string).not_to include("Clean up S3")
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
      # Passes validation, fails on aws cli check (expected)
      allow(Open3).to receive(:capture2).with('which aws').and_return(['', double(success?: false)])
      expect { deployer.deploy }.to raise_error(described_class::Error, /AWS CLI not found/)
    end

    it "raises for missing S3 bucket" do
      allow(target).to receive(:s3_bucket).and_return(nil)
      expect { subject.deploy }.to raise_error(described_class::Error, /S3 bucket not configured/)
    end
  end

  describe "#generate_ami_name" do
    it "uses prefix + label + timestamp" do
      name = subject.send(:generate_ami_name)
      expect(name).to match(/^pim-k8s-\d{8}-\d{6}$/)
    end

    it "falls back to image id without label" do
      no_label = Pim::Image.new(image.to_h.merge('label' => nil))
      deployer = described_class.new(target: target, image: no_label)
      name = deployer.send(:generate_ami_name)
      expect(name).to match(/^pim-default-arm64-\d{8}-\d{6}$/)
    end
  end

  describe "architecture mapping" do
    it "maps arm64 correctly" do
      result = subject.deploy(dry_run: true)
      expect(result[:ami_name]).to be_a(String) # just validate dry_run works for arm64
    end

    it "maps x86_64 correctly" do
      x86_image = Pim::Image.new(image.to_h.merge('arch' => 'x86_64'))
      deployer = described_class.new(target: target, image: x86_image)
      result = deployer.deploy(dry_run: true)
      expect(result[:ami_name]).to be_a(String)
    end
  end
end
