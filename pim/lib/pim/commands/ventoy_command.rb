# frozen_string_literal: true

module Pim
  class VentoyCommand < RestCli::Command
    class Prepare < self
      desc "Install Ventoy to USB device"

      argument :device, required: false, desc: "Device path (e.g., /dev/sdX)"
      option :force, type: :boolean, default: false, aliases: ["-f"], desc: "Force installation without confirmation"

      def call(device: nil, force: false, **)
        manager = Pim::VentoyManager.new
        device ||= manager.config.device

        unless device
          puts "Error: No device specified and no default device in config"
          puts "Usage: pim ventoy prepare /dev/sdX"
          Pim.exit!(1)
        end

        device = manager.validate_device(device)
        Pim.exit!(1) unless device

        unless manager.verify_ventoy_install
          Pim.exit!(1)
        end

        unless manager.check_and_wipe_iso(device)
          Pim.exit!(1)
        end

        unless force
          print "WARNING: This will destroy all data on #{device}. Continue? (y/N) "
          response = $stdin.gets.chomp
          Pim.exit!(1) unless response.downcase == 'y'
        end

        manager.install_ventoy(device)
      end
    end

    class Copy < self
      desc "Mount device and copy ISOs from pim-iso cache"

      argument :device, required: false, desc: "Device path (e.g., /dev/sdX1)"

      def call(device: nil, **)
        manager = Pim::VentoyManager.new
        device ||= manager.config.device

        if device && device !~ /\d+$/
          device = "#{device}1"
          puts "Using partition: #{device}"
        end

        unless device
          puts "Error: No device specified and no default device in config"
          puts "Usage: pim ventoy copy /dev/sdX1"
          Pim.exit!(1)
        end

        unless manager.mount_device(device)
          Pim.exit!(1)
        end

        begin
          manager.copy_isos
        ensure
          manager.unmount_device
        end
      end
    end

    class Status < self
      desc "Check Ventoy installation status"

      argument :device, required: false, desc: "Device path (e.g., /dev/sdX)"

      def call(device: nil, **)
        manager = Pim::VentoyManager.new
        device ||= manager.config.device

        unless device
          puts "Error: No device specified and no default device in config"
          puts "Usage: pim ventoy status /dev/sdX"
          Pim.exit!(1)
        end

        manager.status(device)
      end
    end

    class Show < self
      desc "Show ventoy configuration"

      def call(**)
        Pim::VentoyManager.new.show_config
      end
    end

    class Download < self
      desc "Download and verify Ventoy binaries"

      def call(**)
        manager = Pim::VentoyManager.new
        manager.ensure_ventoy!
      end
    end
  end
end
