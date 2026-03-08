# frozen_string_literal: true

module Pcs
  class RpiHost < Host
    sti_type "rpi"

    def self.detect?(ssh)
      cpuinfo = ssh.read_file("/proc/cpuinfo")
      cpuinfo.include?("Raspberry Pi")
    rescue StandardError
      false
    end

    def self.detect_network_manager(system_cmd)
      if system_cmd.command_exists?("nmcli")
        result = system_cmd.run("nmcli -t -f RUNNING general")
        return :network_manager if result.success? && result.stdout.strip == "running"
      end

      return :netplan if system_cmd.run("test -d /etc/netplan").success?

      :ifupdown
    end

    def render(output_dir, config:)
      puts "  (ops host is self-provisioned during bootstrap)"
    end

    def deploy!(output_dir, config:, state:)
      # No-op — ops host is already configured
    end

    def configure!(config:)
      # No post-provision for the control plane RPi
    end

    def healthy?
      true # we're running on this host
    end
  end
end
