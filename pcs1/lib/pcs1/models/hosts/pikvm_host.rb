# frozen_string_literal: true

module Pcs1
  class PikvmHost < Host
    sti_type "pikvm"

    def default_password
      "root"
    end

    def self.detect?(ssh)
      result = ssh.exec!("systemctl is-active kvmd")
      !result.nil? && result.strip == "active"
    rescue StandardError
      false
    end

    protected

    # PiKVM has a read-only filesystem — need rw/ro around key installation
    def install_key(ssh, pub_key)
      ssh.exec!("rw")
      ssh.exec!("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
      ssh.exec!("echo '#{pub_key}' >> /root/.ssh/authorized_keys")
      ssh.exec!("chmod 600 /root/.ssh/authorized_keys")
      ssh.exec!("ro")
    end
  end
end
