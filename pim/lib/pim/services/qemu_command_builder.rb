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
      @extra_args = []
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

      # CD-ROM
      if @cdrom
        cmd += ['-cdrom', @cdrom]
        cmd += ['-boot', 'd'] # Boot from CD
      end

      # Network
      @netdevs.each do |net|
        case net[:type]
        when 'user'
          netdev = "user,id=#{net[:id]},hostfwd=tcp::#{net[:host_port]}-:#{net[:guest_port]}"
          cmd += ['-netdev', netdev]
          cmd += ['-device', "#{virtio_net_device},netdev=#{net[:id]}"]
        when 'bridged'
          if macos?
            cmd += ['-nic', "vmnet-bridged,id=#{net[:id]},mac=#{net[:mac]}"]
          else
            bridge = net[:bridge] || 'br0'
            cmd += ['-netdev', "bridge,id=#{net[:id]},br=#{bridge}"]
            cmd += ['-device', "#{virtio_net_device},netdev=#{net[:id]},mac=#{net[:mac]}"]
          end
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

    def macos?
      RUBY_PLATFORM.include?('darwin')
    end

    def generate_mac
      "52:54:00:%02x:%02x:%02x" % [rand(256), rand(256), rand(256)]
    end
  end
end
