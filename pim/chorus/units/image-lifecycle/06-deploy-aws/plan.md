---
---

# Plan 06 — Deploy to AWS

## Context

Read before starting:
- `docs/image-lifecycle/README.md` — tier overview
- `docs/image-lifecycle/plan-05-deploy-proxmox.md` — plan 05 (must be complete, establishes deploy pattern)
- `lib/pim/models/targets/aws.rb` — AwsTarget with attributes
- `lib/pim/services/deployers/proxmox_deployer.rb` — reference for deployer pattern
- `lib/pim/commands/image_command.rb` — Deploy command (already handles target dispatch)

## Goal

Implement `pim image deploy <image_id> <target_id>` for AWS targets. This converts a qcow2 to raw format, uploads to S3, imports as an EBS snapshot, and registers as an AMI.

## Background

### AWS AMI creation workflow from qcow2

AWS doesn't accept qcow2 directly. The process:

1. Convert qcow2 → raw: `qemu-img convert -O raw image.qcow2 image.raw`
2. Upload raw to S3: `aws s3 cp image.raw s3://bucket/path/`
3. Import as EBS snapshot: `aws ec2 import-snapshot --disk-container ...`
4. Poll until snapshot import completes
5. Register AMI from snapshot: `aws ec2 register-image --root-device-name /dev/sda1 --block-device-mappings ...`
6. Clean up S3 object (optional, configurable)

### Prerequisites

- AWS CLI installed and configured (or credentials via environment)
- S3 bucket for staging uploads
- IAM permissions for ec2:ImportSnapshot, ec2:RegisterImage, s3:PutObject, etc.
- The `vmimport` service role must exist (standard AWS requirement for VM Import)

### Target data file example

```yaml
# data/targets/aws-us-east.yml
id: aws-us-east
type: aws
name: AWS US East (Virginia)
region: us-east-1
instance_type: t3.medium
ami_name_prefix: pim
s3_bucket: my-pim-images
s3_prefix: imports/
subnet_id: subnet-abc123
security_group_ids: sg-def456
iam_role: vmimport
cleanup_s3: true
```

## Implementation

### Step 1: Add missing attributes to AwsTarget

**File:** `lib/pim/models/targets/aws.rb`

```ruby
class AwsTarget < Target
  sti_type "aws"

  attribute :region, :string
  attribute :instance_type, :string
  attribute :ami_name_prefix, :string
  attribute :s3_bucket, :string
  attribute :s3_prefix, :string
  attribute :subnet_id, :string
  attribute :security_group_ids, :string
  attribute :iam_role, :string
  attribute :cleanup_s3, :boolean

  def deploy(image, build: nil, **options)
    require_relative "../../services/deployers/aws_deployer"
    deployer = Pim::AwsDeployer.new(target: self, image: image, build: build)
    deployer.deploy(**options)
  end

  def region
    super || 'us-east-1'
  end

  def ami_name_prefix
    super || 'pim'
  end

  def s3_prefix
    super || 'pim-imports/'
  end

  def iam_role
    super || 'vmimport'
  end

  def cleanup_s3
    val = super
    val.nil? ? true : val
  end
end
```

### Step 2: Create `Pim::AwsDeployer` service

**File:** `lib/pim/services/deployers/aws_deployer.rb`

```ruby
# frozen_string_literal: true

require 'json'
require 'open3'

module Pim
  class AwsDeployer
    class Error < StandardError; end

    POLL_INTERVAL = 30  # seconds
    IMPORT_TIMEOUT = 3600  # 1 hour max for snapshot import

    def initialize(target:, image:, build: nil)
      @target = target
      @image = image
      @build = build
    end

    # Deploy image to AWS as an AMI
    #
    # Options:
    #   name:      AMI name (default: auto from image)
    #   dry_run:   show what would be done
    def deploy(name: nil, dry_run: false, **_options)
      validate!

      ami_name = name || generate_ami_name
      region = @target.region
      s3_key = "#{@target.s3_prefix}#{@image.id}.raw"

      steps = [
        "Convert #{@image.filename} to raw format",
        "Upload raw image to s3://#{@target.s3_bucket}/#{s3_key}",
        "Import as EBS snapshot (region: #{region})",
        "Poll until snapshot import completes",
        "Register AMI '#{ami_name}' from snapshot",
        @target.cleanup_s3 ? "Clean up S3 object" : nil
      ].compact

      if dry_run
        puts "Dry run — would execute:"
        steps.each_with_index { |s, i| puts "  #{i + 1}. #{s}" }
        return { ami_name: ami_name, region: region, dry_run: true }
      end

      check_aws_cli!

      # 1. Convert to raw
      raw_path = convert_to_raw
      begin
        # 2. Upload to S3
        puts "Uploading to s3://#{@target.s3_bucket}/#{s3_key}..."
        upload_to_s3(raw_path, s3_key)

        # 3. Import snapshot
        puts "Importing as EBS snapshot..."
        snapshot_id = import_snapshot(s3_key)

        # 4. Poll for completion
        puts "Waiting for snapshot import to complete..."
        wait_for_import(snapshot_id)

        # 5. Register AMI
        puts "Registering AMI '#{ami_name}'..."
        ami_id = register_ami(ami_name, snapshot_id)

        # 6. Cleanup S3
        if @target.cleanup_s3
          puts "Cleaning up S3 object..."
          delete_s3_object(s3_key)
        end

        puts
        puts "AMI created: #{ami_id} (#{ami_name})"
        puts "  Region:    #{region}"
        puts "  Snapshot:  #{snapshot_id}"

        { ami_id: ami_id, ami_name: ami_name, snapshot_id: snapshot_id, region: region }
      ensure
        # Always clean up local raw file
        FileUtils.rm_f(raw_path) if raw_path && File.exist?(raw_path)
      end
    end

    private

    def validate!
      raise Error, "Image file missing: #{@image.path}" unless @image.exists?

      unless @image.published? || @image.golden?
        raise Error, "Image '#{@image.id}' must be published before deploying to AWS.\n" \
                     "Run: pim image publish #{@image.id}"
      end

      raise Error, "S3 bucket not configured for target '#{@target.id}'" unless @target.s3_bucket
    end

    def check_aws_cli!
      _, status = Open3.capture2('which aws')
      raise Error, "AWS CLI not found. Install with: pip install awscli" unless status.success?
    end

    def generate_ami_name
      timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
      label = @image.label || @image.id
      "#{@target.ami_name_prefix}-#{label}-#{timestamp}"
    end

    def convert_to_raw
      raw_path = File.join(Dir.tmpdir, "pim-deploy-#{@image.id}.raw")
      puts "Converting to raw format..."
      disk = Pim::QemuDiskImage.new(@image.path)
      disk.convert(raw_path, format: 'raw')
      raw_path
    end

    def upload_to_s3(local_path, s3_key)
      aws_cmd('s3', 'cp', local_path, "s3://#{@target.s3_bucket}/#{s3_key}",
              '--region', @target.region)
    end

    def import_snapshot(s3_key)
      container = {
        Description: "PIM import: #{@image.id}",
        Format: 'raw',
        UserBucket: {
          S3Bucket: @target.s3_bucket,
          S3Key: s3_key
        }
      }

      output = aws_cmd('ec2', 'import-snapshot',
                        '--region', @target.region,
                        '--role-name', @target.iam_role,
                        '--disk-container', JSON.generate(container))

      result = JSON.parse(output)
      task_id = result.dig('ImportTaskId')
      raise Error, "Failed to start snapshot import" unless task_id

      puts "  Import task: #{task_id}"
      task_id
    end

    def wait_for_import(task_id)
      deadline = Time.now + IMPORT_TIMEOUT

      while Time.now < deadline
        output = aws_cmd('ec2', 'describe-import-snapshot-tasks',
                          '--region', @target.region,
                          '--import-task-ids', task_id)

        result = JSON.parse(output)
        task = result.dig('ImportSnapshotTasks', 0, 'SnapshotTaskDetail')
        raise Error, "Import task not found" unless task

        status = task['Status']
        progress = task['Progress'] || '?'

        case status
        when 'completed'
          snapshot_id = task['SnapshotId']
          puts "  Snapshot ready: #{snapshot_id}"
          return snapshot_id
        when 'active'
          puts "  Progress: #{progress}%"
          sleep POLL_INTERVAL
        else
          raise Error, "Snapshot import failed: #{task['StatusMessage']}"
        end
      end

      raise Error, "Snapshot import timed out after #{IMPORT_TIMEOUT}s"
    end

    def register_ami(ami_name, snapshot_id)
      arch = case @image.arch
             when 'arm64', 'aarch64' then 'arm64'
             when 'x86_64', 'amd64' then 'x86_64'
             else 'x86_64'
             end

      block_device = [{
        DeviceName: '/dev/sda1',
        Ebs: {
          SnapshotId: snapshot_id,
          VolumeType: 'gp3',
          DeleteOnTermination: true
        }
      }]

      output = aws_cmd('ec2', 'register-image',
                        '--region', @target.region,
                        '--name', ami_name,
                        '--architecture', arch,
                        '--root-device-name', '/dev/sda1',
                        '--virtualization-type', 'hvm',
                        '--ena-support',
                        '--block-device-mappings', JSON.generate(block_device))

      result = JSON.parse(output)
      ami_id = result['ImageId']
      raise Error, "Failed to register AMI" unless ami_id

      ami_id
    end

    def delete_s3_object(s3_key)
      aws_cmd('s3', 'rm', "s3://#{@target.s3_bucket}/#{s3_key}",
              '--region', @target.region)
    rescue Error
      # Non-fatal — warn but don't fail the deploy
      puts "  Warning: failed to clean up S3 object"
    end

    def aws_cmd(*args)
      cmd = ['aws'] + args
      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise Error, "AWS CLI failed: #{stderr.strip}"
      end

      stdout
    end
  end
end
```

### Step 3: Update `ImageCommand::Deploy` error handling

**File:** `lib/pim/commands/image_command.rb`

Add `Pim::AwsDeployer::Error` to the rescue chain:

```ruby
rescue Pim::ProxmoxDeployer::Error, Pim::AwsDeployer::Error => e
  Pim.exit!(1, message: e.message)
```

Or better — since both deployers use `Error` as an inner class, and the deploy is dispatched polymorphically through `target.deploy`, just rescue `StandardError` from the deploy call and wrap it. Actually, the cleanest approach: rescue any error that includes a message and exit cleanly. The existing rescue on `ProxmoxDeployer::Error` should be broadened:

```ruby
rescue StandardError => e
  Pim.exit!(1, message: e.message)
```

Or define a common `Pim::DeployError` base class. Simplest for now: rescue both explicitly.

### Step 4: Update Deploy command for AWS-specific options

The `Deploy` command already passes `**options` through to `target.deploy`. AWS-specific options (like AMI name) map to the existing `--name` flag. The `--vm-id` flag is Proxmox-specific and will be ignored by the AWS deployer.

No changes needed — the polymorphic dispatch handles this.

## Test Spec

### Unit tests

**File:** `spec/services/deployers/aws_deployer_spec.rb`

- `#validate!` raises for missing image file
- `#validate!` raises for unpublished overlay
- `#validate!` raises for missing S3 bucket
- `#generate_ami_name` uses prefix + label + timestamp
- `#deploy(dry_run: true)` prints steps without executing
- Architecture mapping: arm64 → arm64, x86_64 → x86_64

**File:** `spec/models/targets/aws_spec.rb` (extend)

- Default region is us-east-1
- Default ami_name_prefix is 'pim'
- Default cleanup_s3 is true
- `#deploy` instantiates AwsDeployer

### Manual verification

```bash
# Configure AWS target
# data/targets/aws-us-east.yml (see example in Background)

# Dry run
pim image deploy default-arm64 aws-us-east --dry-run
# Should print conversion, upload, import, register steps

# Actual deploy (requires AWS credentials and S3 bucket)
pim image deploy default-arm64 aws-us-east
# Should: convert to raw, upload to S3, import snapshot, register AMI

# Check deployment history
pim image show default-arm64
# Should show AWS deployment entry with ami_id
```

## Verification

- [ ] `pim image deploy <image> <aws-target> --dry-run` shows steps without executing
- [ ] `pim image deploy <image> <aws-target>` creates AMI end-to-end
- [ ] qcow2 → raw conversion happens in temp directory
- [ ] Raw file cleaned up after deploy (success or failure)
- [ ] Snapshot import progress is displayed
- [ ] AMI registered with correct architecture (arm64 vs x86_64)
- [ ] S3 object cleaned up when `cleanup_s3: true`
- [ ] S3 object preserved when `cleanup_s3: false`
- [ ] Deployment recorded in image registry with ami_id
- [ ] Missing AWS CLI produces helpful error
- [ ] Deploy an unpublished overlay errors with helpful message
- [ ] `bundle exec rspec` passes
