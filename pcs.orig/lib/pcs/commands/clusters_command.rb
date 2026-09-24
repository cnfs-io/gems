# frozen_string_literal: true

module Pcs
  class ClustersCommand < RestCli::Command
    class Install < self
      desc "Install Proxmox VE on bare-metal Debian nodes"

      argument :node_name, required: false, desc: "Hostname of specific node (installs all if omitted)"

      def call(node_name: nil, **)
        site = Pcs::Site.load
        state = Pcs::State.load

        targets = Pcs::Host.load.select { |h| h.role == "node" && h.type == "proxmox" }

        if node_name
          targets = targets.select { |h| h.hostname == node_name }
          if targets.empty?
            $stderr.puts "Error: No proxmox node with hostname '#{node_name}' found"
            exit 1
          end
        end

        if targets.empty?
          $stderr.puts "Error: No proxmox nodes found. Run 'pcs host set' to configure hosts."
          exit 1
        end

        targets.each do |host|
          unless host.ip_on(:compute)
            $stderr.puts "Error: Host #{host.hostname || host.id} has no compute IP set."
            next
          end

          puts "Installing Proxmox VE on #{host.hostname} (#{host.discovered_ip})..."
          installer = Providers::Proxmox::Installer.new(
            host: host,
            site: site,
            state: state
          )

          begin
            installer.install!
            puts "  -> #{host.hostname}: Proxmox VE installed successfully"
          rescue StandardError => e
            $stderr.puts "  -> #{host.hostname}: FAILED — #{e.message}"
          end
        end
      rescue Pcs::ProjectNotFoundError,
             Pcs::SiteNotSetError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end
  end
end
