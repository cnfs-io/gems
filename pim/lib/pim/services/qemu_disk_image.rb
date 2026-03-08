# frozen_string_literal: true

require 'open3'
require 'json'

module Pim
  # Disk image operations via qemu-img
  class QemuDiskImage
    class Error < StandardError; end

    attr_reader :path

    def initialize(path)
      @path = File.expand_path(path)
    end

    # Create a CoW overlay backed by an existing image
    def self.create_overlay(backing_file, dest)
      FileUtils.mkdir_p(File.dirname(dest))
      run_command('qemu-img', 'create', '-f', 'qcow2',
                  '-b', backing_file, '-F', 'qcow2', dest)
      new(dest)
    end

    # Full copy/convert to a new image
    def self.clone(source, dest, format: 'qcow2')
      FileUtils.mkdir_p(File.dirname(dest))
      run_command('qemu-img', 'convert', '-O', format, source, dest)
      new(dest)
    end

    # Create a new disk image
    def self.create(path, size:, format: 'qcow2')
      FileUtils.mkdir_p(File.dirname(path))

      cmd = ['qemu-img', 'create', '-f', format, path, size]
      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise Error, "Failed to create disk image: #{stderr}"
      end

      new(path)
    end

    # Get disk image info
    def info
      cmd = ['qemu-img', 'info', '--output=json', @path]
      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise Error, "Failed to get image info: #{stderr}"
      end

      JSON.parse(stdout)
    end

    # Check if image exists
    def exist?
      File.exist?(@path)
    end

    # Get actual size on disk
    def actual_size
      return nil unless exist?

      info['actual-size']
    end

    # Get virtual size
    def virtual_size
      return nil unless exist?

      info['virtual-size']
    end

    # Convert to another format
    def convert(output_path, format: 'qcow2', compress: false)
      cmd = ['qemu-img', 'convert']
      cmd += ['-c'] if compress
      cmd += ['-O', format, @path, output_path]

      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise Error, "Failed to convert image: #{stderr}"
      end

      QemuDiskImage.new(output_path)
    end

    # Resize the image
    def resize(size)
      cmd = ['qemu-img', 'resize', @path, size]
      stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        raise Error, "Failed to resize image: #{stderr}"
      end

      true
    end

    private_class_method def self.run_command(*cmd)
      output, status = Open3.capture2e(*cmd)
      unless status.success?
        raise Error, "#{cmd.first} failed: #{output}"
      end
      output
    end
  end
end
