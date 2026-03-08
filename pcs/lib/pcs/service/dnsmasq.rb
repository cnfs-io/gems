# frozen_string_literal: true

module Pcs
  module Service
    class Dnsmasq
      def self.start(site:, system_cmd: Adapters::SystemCmd.new)
        unless system_cmd.command_exists?("dnsmasq")
          raise "dnsmasq not found. Run 'pcs init' first to install dependencies."
        end

        resolved = system_cmd.run("systemctl is-active systemd-resolved")
        if resolved.success?
          puts "  -> Disabling systemd-resolved..."
          system_cmd.service("stop", "systemd-resolved")
          system_cmd.service("disable", "systemd-resolved")
        end

        write_config(site: site, system_cmd: system_cmd)

        system_cmd.service("enable", "dnsmasq")
        system_cmd.service("restart", "dnsmasq")
        puts "  -> dnsmasq enabled and running"
      end

      def self.reload(site:, system_cmd: Adapters::SystemCmd.new)
        write_config(site: site, system_cmd: system_cmd)

        # dnsmasq requires full restart to re-read config (SIGHUP only re-reads hosts/leases)
        system_cmd.service("restart", "dnsmasq")
        puts "  -> dnsmasq restarted"
      end

      def self.status(system_cmd: Adapters::SystemCmd.new)
        result = system_cmd.run("systemctl is-active dnsmasq")
        result.success? ? result.stdout.strip : "stopped"
      end

      def self.log_command = "sudo journalctl -f -u dnsmasq"

      def self.status_report(system_cmd: Adapters::SystemCmd.new, pastel: Pastel.new, lines: 20)
        puts pastel.cyan.bold("dnsmasq status")
        puts

        # Service status
        puts pastel.bold("Service:")
        result = system_cmd.run("systemctl is-active dnsmasq")
        st = result.success? ? result.stdout.strip : "inactive"
        puts "  status: #{result.success? ? pastel.green(st) : pastel.red(st)}"
        puts

        # Config file
        puts pastel.bold("Config:")
        project_name = Pcs.project_dir.basename.to_s
        conf = Adapters::Dnsmasq.config_path(project_name)
        if conf.exist?
          puts "  #{conf}: #{pastel.green("present")}"
          conf.each_line do |line|
            line = line.strip
            next if line.empty? || line.start_with?("#")
            puts "    #{line}"
          end
        else
          puts "  #{conf}: #{pastel.red("missing")}"
        end
        puts

        # Mode
        puts pastel.bold("Mode:")
        proxy = Pcs.config.service.dnsmasq.proxy
        puts "  #{proxy ? "proxy DHCP (L1 serves DHCP)" : "full DHCP (dnsmasq serves DHCP)"}"
        puts

        # Ports
        puts pastel.bold("Ports:")
        dhcp = system_cmd.run("ss -ulnp sport = :67")
        if dhcp.stdout.include?(":67")
          puts "  udp/67 (DHCP): #{pastel.green("listening")}"
        else
          puts "  udp/67 (DHCP): #{pastel.red("not listening")}"
        end
        puts

        # Check systemd-resolved conflict
        puts pastel.bold("Conflicts:")
        resolved = system_cmd.run("systemctl is-active systemd-resolved")
        if resolved.success?
          puts "  systemd-resolved: #{pastel.yellow("active (may conflict)")}"
        else
          puts "  systemd-resolved: #{pastel.green("inactive")}"
        end
        puts

        # Recent logs
        puts pastel.bold("Recent logs (last #{lines} lines):")
        logs = system_cmd.run("journalctl -u dnsmasq --no-pager -n #{lines}")
        if logs.success? && !logs.stdout.strip.empty?
          logs.stdout.each_line { |l| puts "  #{l}" }
        else
          puts "  (no logs available)"
        end
      end

      def self.stop(system_cmd: Adapters::SystemCmd.new)
        system_cmd.run("systemctl stop dnsmasq", sudo: true)
        system_cmd.run("systemctl disable dnsmasq", sudo: true)
        puts "  -> dnsmasq stopped and disabled"
      end

      def self.write_config(site:, system_cmd:)
        compute = site.network(:compute)
        compute_subnet = compute.subnet
        raise "compute subnet not set in site.yml. Run 'pcs site add' first." unless compute_subnet

        gateway = compute.gateway
        raise "compute gateway not set in site.yml. Run 'pcs site add' first." unless gateway

        cp_device = Pcs::Host.load.detect { |d| d.role == "cp" }
        raise "No control plane host found. Run 'pcs host set' to assign a host the 'cp' role." unless cp_device

        ops_ip = cp_device.ip_on(:compute) || cp_device.discovered_ip
        raise "Control plane host has no IP. Run 'pcs host set' first." unless ops_ip

        proxy = Pcs.config.service.dnsmasq.proxy

        project_name = Pcs.project_dir.basename.to_s

        Adapters::Dnsmasq.write_config(
          servers_subnet: compute_subnet,
          gateway: gateway,
          ops_ip: ops_ip,
          project_name: project_name,
          proxy: proxy,
          system_cmd: system_cmd
        )
        mode = proxy ? "proxy DHCP" : "full DHCP"
        puts "  -> Wrote #{Adapters::Dnsmasq.config_path(project_name)} (#{mode})"
      end
      private_class_method :write_config
    end
  end
end
