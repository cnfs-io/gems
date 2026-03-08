# frozen_string_literal: true

require 'json'
require 'open3'

module Pim
  class AwsDeployer
    class Error < StandardError; end

    POLL_INTERVAL = 30
    IMPORT_TIMEOUT = 3600

    def initialize(target:, image:, build: nil)
      @target = target
      @image = image
      @build = build
    end

    def deploy(name: nil, dry_run: false, **)
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
        puts "Dry run -- would execute:"
        steps.each_with_index { |s, i| puts "  #{i + 1}. #{s}" }
        return { ami_name: ami_name, region: region, dry_run: true }
      end

      check_aws_cli!

      raw_path = convert_to_raw
      begin
        puts "Uploading to s3://#{@target.s3_bucket}/#{s3_key}..."
        upload_to_s3(raw_path, s3_key)

        puts "Importing as EBS snapshot..."
        task_id = import_snapshot(s3_key)

        puts "Waiting for snapshot import to complete..."
        snapshot_id = wait_for_import(task_id)

        puts "Registering AMI '#{ami_name}'..."
        ami_id = register_ami(ami_name, snapshot_id)

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
      task_id = result['ImportTaskId']
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
