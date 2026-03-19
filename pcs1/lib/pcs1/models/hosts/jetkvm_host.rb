# frozen_string_literal: true

module Pcs1
  class JetkvmHost < Host
    sti_type "jetkvm"

    def self.detect?(ssh)
      result = ssh.exec!("cat /etc/hostname 2>/dev/null")
      !result.nil? && result.strip.downcase.include?("jetkvm")
    rescue StandardError
      false
    end

    def key!
      iface = interfaces.first
      target_ip = iface&.reachable_ip || "unknown"

      Pcs1.logger.info("JetKVM key upload must be done via the web interface.")
      Pcs1.logger.info("Open https://#{target_ip}/ and upload your SSH public key.")
      Pcs1.logger.info("After uploading, verify with: host.key_access?")
    end

    def restart_networking!
      Pcs1.logger.info("Rebooting JetKVM #{hostname || id}...")
      ssh_exec!("reboot")
    rescue StandardError
      # Expected — SSH drops on reboot
    end
  end
end
