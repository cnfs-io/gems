# frozen_string_literal: true

module Pim
  # QEMU command builder for different architectures
  class QemuCommandBuilder
    def initialize(arch:, memory: 2048, cpus: 2, display: false, serial: nil)
      @arch = arch
      @memory = memory
      @cpus = cpus
      @display = display
      @serial = serial
      @drives = []
      @cdrom = nil
      @netdevs = []
      @usb_disks = []
      @extra_args = []
    end

    # Pass a host disk (e.g. /dev/rdisk5) to the guest as a USB mass-storage device
    def add_usb_disk(path)
      @usb_disks << path
      self
    end

    # Add a disk drive
    def add_drive(path, format: 'qcow2', if_type: 'virtio', index: 0)
      @drives << { path: path, format: format, if_type: if_type, index: index }
      self
    end

    # Set CD-ROM/ISO
    def set_cdrom(path)
      @cdrom = path
      self
    end

    # Add user-mode networking with port forwarding
    def add_user_net(host_port:, guest_port: 22, id: 'net0')
      @netdevs << {
        type: 'user',
        id: id,
        host_port: host_port,
        guest_port: guest_port
      }
      self
    end

    # Add bridged networking (VM gets LAN IP)
    # macOS: vmnet-bridged via en0
    # Linux: bridge netdev (requires /etc/qemu/bridge.conf)
    def add_bridged_net(id: 'net0', bridge: nil, mac: nil)
      @netdevs << {
        type: 'bridged',
        id: id,
        bridge: bridge,
        mac: mac || generate_mac
      }
      self
    end

    # Add kernel boot parameters (for preseed)
    def set_kernel_args(kernel_args)
      @kernel_args = kernel_args
      self
    end

    # Add extra QEMU arguments
    def extra_args(*args)
      @extra_args += args.flatten
      self
    end

    # Build the command array
    def build
      cmd = [qemu_binary]

      # Machine and acceleration
      cmd += machine_args

      # CPU and memory
      cmd += ['-smp', @cpus.to_s]
      cmd += ['-m', @memory.to_s]

      # Display
      unless @display
        cmd += ['-nographic']
      end

      # Drives
      @drives.each do |drive|
        cmd += ['-drive', "file=#{drive[:path]},format=#{drive[:format]},if=#{drive[:if_type]},index=#{drive[:index]}"]
      end

      # Network (before the CD-ROM so the NIC can claim its pinned PCI slot)
      @netdevs.each do |net|
        case net[:type]
        when 'user'
          netdev = "user,id=#{net[:id]},hostfwd=tcp::#{net[:host_port]}-:#{net[:guest_port]}"
          cmd += ['-netdev', netdev]
          cmd += ['-device', "#{virtio_net_device},netdev=#{net[:id]}#{net_pci_addr}"]
        when 'bridged'
          if macos?
            cmd += ['-nic', "vmnet-bridged,id=#{net[:id]},ifname=#{net[:bridge] || 'en0'},mac=#{net[:mac]}"]
          else
            bridge = net[:bridge] || 'br0'
            cmd += ['-netdev', "bridge,id=#{net[:id]},br=#{bridge}"]
            cmd += ['-device', "#{virtio_net_device},netdev=#{net[:id]},mac=#{net[:mac]}#{net_pci_addr}"]
          end
        end
      end

      # CD-ROM
      if @cdrom
        if arm?
          # virt has no IDE bus: -cdrom becomes a virtio-blk disk the installer can't detect as a CD
          cmd += ['-device', 'virtio-scsi-pci,id=scsi0']
          cmd += ['-drive', "file=#{@cdrom},media=cdrom,if=none,id=cd0,readonly=on"]
          cmd += ['-device', 'scsi-cd,drive=cd0,bus=scsi0.0']
        else
          cmd += ['-cdrom', @cdrom]
          cmd += ['-boot', 'd'] # Boot from CD
        end
      end

      # USB disks (after the NIC so it keeps its PCI slot)
      unless @usb_disks.empty?
        cmd += ['-device', 'qemu-xhci,id=xhci']
        @usb_disks.each_with_index do |path, i|
          cmd += ['-drive', "file=#{path},format=raw,if=none,id=usbdisk#{i}"]
          cmd += ['-device', "usb-storage,bus=xhci.0,drive=usbdisk#{i},removable=on"]
        end
      end

      # Serial console
      if @serial
        cmd += ['-serial', @serial]
      elsif !@display
        cmd += ['-serial', 'mon:stdio']
      end

      # Extra args
      cmd += @extra_args unless @extra_args.empty?

      cmd
    end

    # Get command as string (for display)
    def to_s
      build.map { |arg| arg.include?(' ') ? "\"#{arg}\"" : arg }.join(' ')
    end

    private

    def qemu_binary
      case @arch
      when 'arm64', 'aarch64'
        'qemu-system-aarch64'
      when 'x86_64', 'amd64'
        'qemu-system-x86_64'
      else
        raise "Unsupported architecture: #{@arch}"
      end
    end

    def machine_args
      case @arch
      when 'arm64', 'aarch64'
        if macos?
          ['-machine', 'virt,accel=hvf,highmem=on', '-cpu', 'host']
        else
          if File.exist?('/dev/kvm')
            ['-machine', 'virt,accel=kvm', '-cpu', 'host']
          else
            ['-machine', 'virt', '-cpu', 'cortex-a72']
          end
        end
      when 'x86_64', 'amd64'
        if macos?
          ['-machine', 'q35,accel=hvf', '-cpu', 'host']
        else
          if File.exist?('/dev/kvm')
            ['-machine', 'q35,accel=kvm', '-cpu', 'host']
          else
            ['-machine', 'q35', '-cpu', 'qemu64']
          end
        end
      else
        raise "Unsupported architecture: #{@arch}"
      end
    end

    def virtio_net_device
      case @arch
      when 'arm64', 'aarch64'
        'virtio-net-pci'
      when 'x86_64', 'amd64'
        'virtio-net-pci'
      else
        'e1000'
      end
    end

    def arm?
      %w[arm64 aarch64].include?(@arch)
    end

    # Pin the first NIC to PCI slot 1 on arm64 so its name (enp0s1) is the same
    # in the installer (which has the extra SCSI CD-ROM controller) and the installed system.
    # x86 q35 needs no pin: VGA holds slot 1 and the CD-ROM is on the built-in SATA controller.
    def net_pci_addr
      arm? && @netdevs.size == 1 ? ',addr=0x1' : ''
    end

    def macos?
      RUBY_PLATFORM.include?('darwin')
    end

    def generate_mac
      "52:54:00:%02x:%02x:%02x" % [rand(256), rand(256), rand(256)]
    end
  end
end
