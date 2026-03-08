# frozen_string_literal: true

module Pcs
  class TruenasHost < Host
    sti_type "truenas"

    def self.detect?(ssh)
      result = ssh.exec!("command -v midclt")
      !result.nil? && result.include?("midclt")
    rescue StandardError
      false
    end

    def render(output_dir, config:)
      write_local(output_dir, "/root/.ssh/authorized_keys", config.ssh_public_key + "\n")
      write_local(output_dir, "/provision.sh", render_provision_script)
    end

    def deploy!(output_dir, config:, state:)
      with_ssh_probe(config: config, state: state) do |ssh|
        configure_servers_interface(ssh)
        configure_storage_interface(ssh) if interface_on(:storage)
        set_hostname_via_midclt(ssh)
        push_ssh_key(ssh, output_dir)
        apply_network(ssh)
      end
    end

    def configure!(config:)
      # NAS pool/dataset setup handled by nas service (Phase 4)
    end

    def healthy?
      with_ssh(user: "root", config: Pcs::Config.load, state: Pcs::State.load) do |ssh|
        result = ssh.exec!("midclt call system.ready")
        result&.strip == "true"
      end
    rescue StandardError
      false
    end

    private

    def configure_servers_interface(ssh)
      ip = ip_on(:compute)
      prefix = compute_network.subnet.split("/").last
      gateway = compute_network.gateway

      ssh.exec!(
        "midclt call interface.update ens0 " \
        "'{\"ipv4_dhcp\": false, \"aliases\": [{\"address\": \"#{ip}\", \"netmask\": #{prefix}}]}'"
      )
      ssh.exec!("midclt call network.configuration.update '{\"ipv4gateway\": \"#{gateway}\"}'")
    end

    def configure_storage_interface(ssh)
      ip = ip_on(:storage)
      prefix = storage_network.subnet.split("/").last

      ssh.exec!(
        "midclt call interface.update ens1 " \
        "'{\"ipv4_dhcp\": false, \"aliases\": [{\"address\": \"#{ip}\", \"netmask\": #{prefix}}]}'"
      )
    end

    def set_hostname_via_midclt(ssh)
      ssh.exec!("midclt call network.configuration.update " \
      "'{\"hostname\": \"#{hostname}\", \"domain\": \"#{site.domain}\"}'")
    end

    def push_ssh_key(ssh, output_dir)
      pub_key = (output_dir / "root/.ssh/authorized_keys").read.strip
      ssh.exec!("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
      ssh.exec!("echo '#{pub_key}' >> /root/.ssh/authorized_keys")
      ssh.exec!("chmod 600 /root/.ssh/authorized_keys")
    end

    def apply_network(ssh)
      ssh.exec!("midclt call interface.commit")
      ssh.exec!("midclt call interface.checkin")
    end

    def render_provision_script
      ip = ip_on(:compute)
      prefix = compute_network.subnet.split("/").last
      gateway = compute_network.gateway
      lines = [
        "#!/bin/sh",
        "# TrueNAS provision commands for #{hostname}",
        "",
        "midclt call interface.update ens0 '{\"ipv4_dhcp\": false, " \
        "\"aliases\": [{\"address\": \"#{ip}\", \"netmask\": #{prefix}}]}'",
        "midclt call network.configuration.update '{\"ipv4gateway\": \"#{gateway}\"}'",
      ]

      if interface_on(:storage)
        sip = ip_on(:storage)
        sprefix = storage_network.subnet.split("/").last
        lines += [
          "",
          "midclt call interface.update ens1 '{\"ipv4_dhcp\": false, " \
          "\"aliases\": [{\"address\": \"#{sip}\", \"netmask\": #{sprefix}}]}'",
        ]
      end

      lines += [
        "",
        "midclt call network.configuration.update " \
        "'{\"hostname\": \"#{hostname}\", \"domain\": \"#{site.domain}\"}'",
        "",
        "midclt call interface.commit",
        "midclt call interface.checkin",
        ""
      ]

      lines.join("\n")
    end
  end
end
