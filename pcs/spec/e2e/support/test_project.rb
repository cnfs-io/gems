# frozen_string_literal: true

require "yaml"
require_relative "e2e_root"
require "pcs/platform/arch"
require "pcs/platform/os"

module Pcs
  module E2E
    class TestProject
      SITE_NAME = "e2e"
      VM_HOSTNAME = "e2e-node1"
      VM_MAC = "52:54:00:e2:e2:01"
      VM_STATIC_IP = "10.99.0.41"
      OPS_IP = TestBridge::BRIDGE_IP.split("/").first

      attr_reader :os

      def initialize(arch: Platform::Arch.native, os: "debian-bookworm", base_dir: DIRS[:project])
        @arch = arch
        @os = os
        @base_dir = base_dir
      end

      def scaffold
        cleanup
        E2E.setup_dirs!

        # Use pcs new to scaffold, then overlay test data
        system_cmd = Pcs::Adapters::SystemCmd.new
        Dir.chdir(@base_dir.parent) do
          system_cmd.run!("pcs new #{@base_dir.basename}")
        end

        write_site_config
        write_host_data
        write_env
        generate_ssh_keys

        # Point Netboot at test-local directory
        Pcs.config.service.netboot.netboot_dir = DIRS[:netboot]

        @base_dir
      end

      def project_dir
        @base_dir
      end

      def ssh_private_key_path
        DIRS[:ssh] / "e2e_key"
      end

      def cleanup
        # Reset Netboot dir to default
        Pcs.config.service.netboot.netboot_dir = Pathname.new("/opt/pcs/netboot")

        E2E.cleanup!
      end

      private

      def write_site_config
        site_dir = @base_dir / "sites" / SITE_NAME
        site_dir.mkpath

        site_yml = {
          "name" => SITE_NAME,
          "domain" => "e2e.test",
          "timezone" => "UTC",
          "ssh_key" => (DIRS[:ssh] / "authorized_keys").to_s,
          "networks" => {
            "compute" => {
              "subnet" => "10.99.0.0/24",
              "gateway" => "10.99.0.1",
              "dns_resolvers" => ["10.99.0.1", "1.1.1.1"]
            },
            "storage" => {
              "subnet" => "10.99.1.0/24",
              "gateway" => "10.99.1.1",
              "dns_resolvers" => ["10.99.1.1"]
            }
          }
        }

        (site_dir / "site.yml").write(YAML.dump(site_yml))
      end

      def write_host_data
        site_dir = @base_dir / "sites" / SITE_NAME
        hosts_yml = {
          "records" => [
            {
              "id" => "1",
              "hostname" => VM_HOSTNAME,
              "mac" => VM_MAC,
              "type" => "proxmox",
              "role" => "node",
              "arch" => @arch,
              "status" => "discovered",
              "connect_as" => "admin",
              "discovered_ip" => VM_STATIC_IP,
              "compute_ip" => VM_STATIC_IP,
              "site_id" => SITE_NAME,
              "preseed_device" => "/dev/vda",
              "preseed_interface" => "eth0",
              "discovered_at" => Time.now.iso8601,
              "last_seen_at" => Time.now.iso8601
            },
            {
              "id" => "2",
              "hostname" => "e2e-cp",
              "type" => "rpi",
              "role" => "cp",
              "arch" => @arch,
              "status" => "provisioned",
              "discovered_ip" => OPS_IP,
              "compute_ip" => OPS_IP,
              "site_id" => SITE_NAME,
              "discovered_at" => Time.now.iso8601,
              "last_seen_at" => Time.now.iso8601
            }
          ]
        }

        (site_dir / "hosts.yml").write(YAML.dump(hosts_yml))
      end

      def write_env
        (@base_dir / ".env").write("PCS_SITE=#{SITE_NAME}\n")
      end

      def generate_ssh_keys
        DIRS[:ssh].mkpath
        private_key = DIRS[:ssh] / "e2e_key"
        public_key = DIRS[:ssh] / "e2e_key.pub"
        authorized_keys = DIRS[:ssh] / "authorized_keys"

        unless private_key.exist?
          system("ssh-keygen -t ed25519 -f #{private_key} -N '' -q")
          authorized_keys.write(public_key.read)
        end
      end
    end
  end
end
