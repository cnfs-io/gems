# frozen_string_literal: true

require "rbconfig"
require "socket"

module Pcs
  module Adapters
    # Whether an address answers: a ping (the installer answers these long
    # before anything listens on a port), or a TCP port.
    class Probe
      def initialize(system: SystemCmd.new)
        @system = system
      end

      def ping?(ip)
        # One echo request, waiting a second (-W is seconds on Linux, ms on macOS).
        wait = RbConfig::CONFIG["host_os"].include?("darwin") ? "1000" : "1"
        @system.run("ping", "-c", "1", "-W", wait, ip).success?
      end

      def port?(ip, port, timeout: 2)
        Socket.tcp(ip, port, connect_timeout: timeout).close
        true
      rescue SystemCallError, SocketError, IOError
        false
      end
    end
  end
end
