# frozen_string_literal: true

module Pcs1
  class PikvmHost < Host
    sti_type "pikvm"

    def self.detect?(ssh)
      result = ssh.exec!("systemctl is-active kvmd")
      !result.nil? && result.strip == "active"
    rescue StandardError
      false
    end

    def restart_networking!
      Pcs1.logger.info("Rebooting PiKVM #{hostname || id}...")
      ssh_exec!("reboot")
    rescue StandardError
      # Expected — SSH drops on reboot
    end

    protected

    def install_key(ssh, pub_key)
      ssh.exec!("rw")
      super
      ssh.exec!("ro")
    end
  end
end
