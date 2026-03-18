# frozen_string_literal: true

module Pcs1
  class JetkvmHost < Host
    sti_type "jetkvm"

    def self.detect?(ssh)
      # JetKVM identification — check for JetKVM-specific markers
      result = ssh.exec!("cat /etc/hostname 2>/dev/null")
      !result.nil? && result.strip.downcase.include?("jetkvm")
    rescue StandardError
      false
    end

    # JetKVM requires manual key upload via web interface.
    # This method reminds the operator and does not attempt SSH.
    def key!
      iface = interfaces.first
      target_ip = iface&.reachable_ip || "unknown"

      puts "  JetKVM key upload must be done via the web interface."
      puts "  Open https://#{target_ip}/ and upload your SSH public key."
      puts "  After uploading, verify with: host.key_access?"
    end
  end
end
