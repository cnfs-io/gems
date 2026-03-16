# frozen_string_literal: true

module Pcs
  class PikvmHost < Host
    sti_type "pikvm"

    def self.detect?(ssh)
      result = ssh.exec!("systemctl is-active kvmd")
      !result.nil? && result.strip == "active"
    rescue StandardError
      false
    end

    def render(output_dir)
      write_local(output_dir, "/etc/systemd/network/eth0.network", render_network)
      write_local(output_dir, "/etc/hostname", fqdn + "\n")
      pub_key = site.ssh_public_key_content
      write_local(output_dir, "/root/.ssh/authorized_keys", pub_key + "\n") if pub_key
    end

    def deploy!(output_dir, state:)
      with_ssh_probe(state: state) do |ssh|
        ssh.exec!("rw")
        push_file(ssh, output_dir, "/etc/systemd/network/eth0.network")
        push_file(ssh, output_dir, "/etc/hostname")
        ssh.exec!("hostnamectl set-hostname #{fqdn}")
        push_ssh_key(ssh, output_dir)
        ssh.exec!("systemctl restart systemd-networkd")
        ssh.exec!("ro")
      end
    end

    def configure!
      # No post-provision for PiKVM
    end

    def healthy?
      with_ssh(user: "root", state: Pcs::State.load) do |ssh|
        result = ssh.exec!("systemctl is-active kvmd")
        result&.strip == "active"
      end
    rescue StandardError
      false
    end

    private

    def render_network
      ip = ip_on(:compute)
      prefix = compute_network.subnet.split("/").last
      gateway = compute_network.gateway
      dns = compute_network.dns_resolvers&.first

      <<~NETWORK
        [Match]
        Name=eth0

        [Network]
        Address=#{ip}/#{prefix}
        Gateway=#{gateway}
        DNS=#{dns}
      NETWORK
    end

    def push_file(ssh, output_dir, remote_path)
      content = (output_dir / remote_path.delete_prefix("/")).read
      ssh.exec!("cat > #{remote_path} <<'EOF'\n#{content}EOF")
    end

    def push_ssh_key(ssh, output_dir)
      pub_key = (output_dir / "root/.ssh/authorized_keys").read.strip
      ssh.exec!("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
      ssh.exec!("echo '#{pub_key}' >> /root/.ssh/authorized_keys")
      ssh.exec!("chmod 600 /root/.ssh/authorized_keys")
    end
  end
end
