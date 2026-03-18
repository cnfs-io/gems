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

    protected

    # PiKVM has a read-only filesystem — wrap with rw/ro around base key installation
    def install_key(ssh, pub_key)
      ssh.exec!("rw")
      super
      ssh.exec!("ro")
    end
  end
end
