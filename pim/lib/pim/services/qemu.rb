# frozen_string_literal: true

require 'open3'
require 'socket'

module Pim
  # QEMU utility methods
  module Qemu
    EFI_FIRMWARE_PATHS = [
      '/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
      '/usr/local/share/qemu/edk2-aarch64-code.fd',
      '/usr/share/qemu/edk2-aarch64-code.fd',
      '/usr/share/AAVMF/AAVMF_CODE.fd',
      '/usr/share/qemu-efi-aarch64/QEMU_EFI.fd'
    ].freeze

    EFI_VARS_PATHS = [
      '/opt/homebrew/share/qemu/edk2-arm-vars.fd',
      '/usr/local/share/qemu/edk2-arm-vars.fd',
      '/usr/share/qemu/edk2-arm-vars.fd',
      '/usr/share/AAVMF/AAVMF_VARS.fd'
    ].freeze

    def self.find_efi_firmware
      EFI_FIRMWARE_PATHS.find { |p| File.exist?(p) }
    end

    def self.find_efi_vars_template
      EFI_VARS_PATHS.find { |p| File.exist?(p) }
    end

    # Find an available port.
    # Binds on 0.0.0.0 because QEMU's hostfwd binds on all interfaces.
    def self.find_available_port(start_port: 2222, max_attempts: 100)
      (start_port..start_port + max_attempts).each do |port|
        begin
          socket = TCPServer.new('0.0.0.0', port)
          socket.close
          return port
        rescue Errno::EADDRINUSE
          next
        end
      end
      raise "No available port found in range #{start_port}-#{start_port + max_attempts}"
    end

    # Runtime directory for sockets, PIDs, state files
    def self.runtime_dir
      dir = if ENV['XDG_RUNTIME_DIR']
              File.join(ENV['XDG_RUNTIME_DIR'], 'pim')
            else
              File.join('/tmp', 'pim')
            end
      FileUtils.mkdir_p(dir)
      dir
    end

    # Check if qemu is installed
    def self.check_dependencies
      missing = []

      %w[qemu-system-aarch64 qemu-system-x86_64 qemu-img].each do |cmd|
        _, status = Open3.capture2("which #{cmd}")
        missing << cmd unless status.success?
      end

      missing
    end
  end
end
