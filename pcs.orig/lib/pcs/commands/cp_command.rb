# frozen_string_literal: true

require "tty-prompt"

module Pcs
  class CpCommand < RestCli::Command
    class Setup < self
      desc "Configure this host as control plane (hostname, static IP)"

      def call(**)
        site = Pcs::Site.load
        system_cmd = Adapters::SystemCmd.new
        prompt = TTY::Prompt.new

        cp_host = Pcs::Host.load.detect { |h| h.role == "cp" }
        raise "No control plane host found. Run 'pcs host set' to assign the 'cp' role." unless cp_host

        ops_ip = cp_host.ip_on(:compute) || cp_host.discovered_ip
        raise "Control plane host has no IP. Run 'pcs host set' first." unless ops_ip

        domain = site.domain || "local"
        compute = site.network(:compute)
        gateway = compute.gateway
        prefix_len = compute.subnet&.split("/")&.last&.to_i || 24
        dns_resolvers = compute.dns_resolvers || [gateway]

        short_hostname = prompt.ask("Hostname:", default: "ops1")
        fqdn = "#{short_hostname}.#{domain}"

        puts
        puts "  Hostname: #{fqdn}"
        puts "  Static IP: #{ops_ip}/#{prefix_len}"
        puts "  Gateway: #{gateway}"
        puts "  DNS: #{dns_resolvers.join(", ")}"
        puts

        unless prompt.yes?("Apply this configuration?", default: true)
          puts "Aborted."
          return
        end

        cp_service = Service::ControlPlane.new(system_cmd: system_cmd)

        puts "  -> Writing /etc/hosts"
        hosts_content = <<~HOSTS
          127.0.0.1 localhost
          #{ops_ip} #{fqdn} #{short_hostname}
        HOSTS
        system_cmd.file_write("/etc/hosts", hosts_content, sudo: true)

        puts "  -> Setting hostname to #{fqdn}"
        system_cmd.run!("hostnamectl set-hostname #{fqdn}", sudo: true)

        puts "  -> Configuring static IP on eth0"
        nm_type = Pcs::RpiHost.detect_network_manager(system_cmd)
        cp_service.apply_static_ip(nm_type, ip: ops_ip, prefix_len: prefix_len,
                                            gateway: gateway, dns_resolvers: dns_resolvers)

        puts
        puts "  !! Your SSH session will disconnect after network restart."
        puts "  !! Reconnect at: ssh #{ENV.fetch("USER", "pi")}@#{ops_ip}"
        puts

        return unless prompt.yes?("Proceed with network restart?", default: true)

        puts "  -> Restarting networking..."
        cp_service.restart_networking(nm_type)
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end
  end
end
