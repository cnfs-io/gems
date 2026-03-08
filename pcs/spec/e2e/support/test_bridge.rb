# frozen_string_literal: true

require_relative "e2e_root"

module Pcs
  module E2E
    class TestBridge
      BRIDGE_NAME = "pcs-test0"
      TAP_NAME = "pcs-tap0"
      BRIDGE_IP = "10.99.0.1/24"
      SUBNET = "10.99.0.0/24"

      def initialize(system_cmd: Pcs::Adapters::SystemCmd.new)
        @cmd = system_cmd
      end

      def up
        return if bridge_exists?

        @cmd.run!("ip link add #{BRIDGE_NAME} type bridge", sudo: true)
        @cmd.run!("ip addr add #{BRIDGE_IP} dev #{BRIDGE_NAME}", sudo: true)
        @cmd.run!("ip link set #{BRIDGE_NAME} up", sudo: true)

        @cmd.run!("ip tuntap add dev #{TAP_NAME} mode tap", sudo: true)
        @cmd.run!("ip link set #{TAP_NAME} master #{BRIDGE_NAME}", sudo: true)
        @cmd.run!("ip link set #{TAP_NAME} up", sudo: true)

        @cmd.run!("sysctl -w net.ipv4.ip_forward=1", sudo: true)
      end

      def down
        @cmd.run("ip link set #{TAP_NAME} down", sudo: true)
        @cmd.run("ip tuntap del dev #{TAP_NAME} mode tap", sudo: true)
        @cmd.run("ip link set #{BRIDGE_NAME} down", sudo: true)
        @cmd.run("ip link del #{BRIDGE_NAME}", sudo: true)
      end

      def bridge_exists?
        @cmd.run("ip link show #{BRIDGE_NAME}").success?
      end

      def bridge_ip
        BRIDGE_IP.split("/").first
      end
    end
  end
end
