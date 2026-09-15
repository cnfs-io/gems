# frozen_string_literal: true

require 'open3'

module Pim
  # Host USB disks passed to a VM as USB mass-storage devices.
  # A disk is given as "VID:PID" (macOS; stable across replugs) or a device path.
  module UsbDisk
    class Error < StandardError; end

    ID_PATTERN = /\A\h{4}:\h{4}\z/

    # Spec -> host block device, e.g. "058f:6387" -> "/dev/disk5"
    def self.resolve(spec)
      spec = spec.to_s.strip

      if spec.match?(ID_PATTERN)
        raise Error, "USB IDs like #{spec} only work on macOS; use a device path (e.g. /dev/disk/by-id/usb-...)" unless macos?

        disk = macos_disks[spec.downcase]
        raise Error, "USB disk #{spec} not found (plugged in? list disks with: ventoy list)" unless disk

        "/dev/#{disk}"
      else
        path = File.realpath(spec) rescue nil
        raise Error, "#{spec} is not a block device" unless path && File.blockdev?(path)

        path
      end
    end

    # { "058f:6387" => "disk5" } for USB devices that have a whole-disk BSD name
    def self.macos_disks(ioreg_output = nil)
      ioreg_output ||= Open3.capture2('ioreg', '-r', '-c', 'IOUSBHostDevice', '-l', '-w0').first
      disks = {}
      vid = pid = nil

      ioreg_output.each_line do |line|
        case line
        when /"idVendor" = (\d+)/ then vid = Regexp.last_match(1).to_i
        when /"idProduct" = (\d+)/ then pid = Regexp.last_match(1).to_i
        when /"BSD Name" = "(disk\d+)"/
          disks[format('%04x:%04x', vid, pid)] ||= Regexp.last_match(1) if vid && pid
        end
      end

      disks
    end

    # Path QEMU should open: the raw device on macOS (the buffered /dev/diskN is much slower)
    def self.qemu_path(device)
      macos? ? device.sub(%r{\A/dev/disk}, '/dev/rdisk') : device
    end

    # The host must not have the disk's volumes mounted while the guest writes to it
    def self.release(device)
      if macos?
        output, status = Open3.capture2e('diskutil', 'unmountDisk', device)
        raise Error, "Could not unmount #{device}: #{output.strip}" unless status.success?
      else
        mounts, = Open3.capture2('lsblk', '-nro', 'MOUNTPOINT', device)
        raise Error, "#{device} has mounted partitions; unmount them first" unless mounts.strip.empty?
      end
    end

    def self.macos?
      RUBY_PLATFORM.include?('darwin')
    end
  end
end
