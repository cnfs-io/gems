# frozen_string_literal: true

require "net/ssh"
require "socket"

module Pcs
  module Adapters
    class SSH
      # Quick TCP check before attempting SSH auth
      def self.port_open?(host, port = 22, timeout = 2)
        Socket.tcp(host, port, connect_timeout: timeout) { true }
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, SocketError
        false
      end

      # Connect to a host with the PCS management key
      def self.connect(host:, key:, user: "root", &block)
        Net::SSH.start(
          host,
          user,
          keys: [key.to_s],
          non_interactive: true,
          verify_host_key: :never,
          timeout: 10
        ) do |ssh|
          block.call(ssh)
        end
      end

      # Try to connect with common credentials for discovery
      def self.probe(host:, &block)
        return nil unless port_open?(host)

        disc = Pcs.config.discovery
        users = disc.users
        passwords = disc.passwords

        users.each do |user|
          passwords.each do |password|
            return Net::SSH.start(
              host, user,
              password: password,
              non_interactive: true,
              verify_host_key: :never,
              timeout: 5,
              &block
            )
          rescue Net::SSH::AuthenticationFailed, Net::SSH::ConnectionTimeout, Errno::ECONNREFUSED
            next
          end

          # Try key-based auth (default keys)
          begin
            return Net::SSH.start(
              host, user,
              non_interactive: true,
              verify_host_key: :never,
              timeout: 5,
              &block
            )
          rescue Net::SSH::AuthenticationFailed, Net::SSH::ConnectionTimeout, Errno::ECONNREFUSED
            next
          end
        end
        nil
      end

      # Detect host type by running strategy detection over SSH
      def self.detect_type(host_ip)
        probe(host: host_ip) do |ssh|
          return :proxmox if Pcs::PveHost.detect?(ssh)
          return :truenas if Pcs::TruenasHost.detect?(ssh)
          return :pikvm   if Pcs::PikvmHost.detect?(ssh)
          return :rpi     if Pcs::RpiHost.detect?(ssh)
          :unknown
        end
      end
    end
  end
end
