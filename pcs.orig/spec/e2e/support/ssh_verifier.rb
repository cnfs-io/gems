# frozen_string_literal: true

require "open3"
require "socket"

module Pcs
  module E2E
    class SshVerifier
      DEFAULT_TIMEOUT = 300
      POLL_INTERVAL = 10

      def initialize(host:, user: "admin", key_path: nil)
        @host = host
        @user = user
        @key_path = key_path
      end

      def wait_for_ssh(timeout: DEFAULT_TIMEOUT)
        deadline = Time.now + timeout

        loop do
          raise "SSH to #{@host} not available after #{timeout}s" if Time.now > deadline

          if port_open?(@host, 22)
            begin
              run("echo ok")
              return true
            rescue StandardError
              # not ready yet
            end
          end

          sleep POLL_INTERVAL
        end
      end

      def run(command)
        ssh_args = [
          "ssh",
          "-o", "StrictHostKeyChecking=no",
          "-o", "UserKnownHostsFile=/dev/null",
          "-o", "ConnectTimeout=5",
          "-o", "BatchMode=yes"
        ]
        ssh_args += ["-i", @key_path] if @key_path
        ssh_args += ["#{@user}@#{@host}", command]

        stdout, stderr, status = Open3.capture3(*ssh_args)
        raise "SSH command failed: #{command}\nstderr: #{stderr}" unless status.success?

        stdout.strip
      end

      def assert_hostname(expected)
        actual = run("hostname -f")
        raise "Hostname mismatch: expected #{expected}, got #{actual}" unless actual == expected
        true
      end

      def assert_ip(interface, expected)
        actual = run("ip -4 addr show #{interface} | grep -oP 'inet \\K[\\d.]+'")
        raise "IP mismatch on #{interface}: expected #{expected}, got #{actual}" unless actual == expected
        true
      end

      def assert_file_exists(path)
        run("test -f #{path}")
        true
      rescue StandardError
        raise "File not found: #{path}"
      end

      def assert_file_contains(path, pattern)
        run("grep -q '#{pattern}' #{path}")
        true
      rescue StandardError
        raise "Pattern '#{pattern}' not found in #{path}"
      end

      def assert_service_active(service_name)
        actual = run("systemctl is-active #{service_name}")
        raise "Service #{service_name} is #{actual}, expected active" unless actual == "active"
        true
      end

      private

      def port_open?(host, port)
        Socket.tcp(host, port, connect_timeout: 3) { true }
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
             Errno::ETIMEDOUT, SocketError
        false
      end
    end
  end
end
