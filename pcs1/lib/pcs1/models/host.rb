# frozen_string_literal: true

require "net/ssh"

module Pcs1
  class Host < FlatRecord::Base
    source "hosts"
    sti_column :type

    attribute :hostname, :string
    attribute :role, :string
    attribute :type, :string
    attribute :arch, :string
    attribute :status, :string, default: "discovered"
    attribute :site_id, :string

    belongs_to :site, class_name: "Pcs1::Site"
    has_many :interfaces, class_name: "Pcs1::Interface", foreign_key: :host_id

    # --- State machine ---

    STATES = %w[discovered keyed configured provisioned].freeze
    TRANSITIONS = {
      "discovered" => %w[keyed],
      "keyed"      => %w[configured],
      "configured" => %w[provisioned],
    }.freeze

    def transition_to!(new_status)
      allowed = TRANSITIONS[status] || []
      unless allowed.include?(new_status)
        raise "Invalid transition: cannot go from '#{status}' to '#{new_status}'. " \
              "Allowed: #{allowed.join(", ")}"
      end

      self.status = new_status
      save!
    end

    # --- Local host detection ---

    def self.local_ips
      Platform.current.local_ips
    end

    def self.local
      local_ips.each do |ip|
        iface = Pcs1::Interface.find_by(ip: ip) ||
                Pcs1::Interface.find_by(discovered_ip: ip)
        return iface.host if iface
      end
      nil
    end

    # --- Keying ---

    # Override in STI subclasses to provide default credentials
    def default_user
      "root"
    end

    def default_password
      raise NotImplementedError, "#{self.class} must implement #default_password"
    end

    def key!
      pub_key = site.ssh_public_key_content
      raise "No SSH public key found at #{site.ssh_key}" unless pub_key

      iface = interfaces.first
      raise "Host has no interfaces — run 'network scan' first" unless iface

      target_ip = iface.reachable_ip
      raise "No reachable IP for host #{id}" unless target_ip

      # Step 1: SSH in with default credentials and push the key
      puts "  Connecting to #{target_ip} as #{default_user}..."
      Net::SSH.start(target_ip, default_user,
                     password: default_password,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        install_key(ssh, pub_key)
      end

      # Step 2: Verify key-based access via SSH agent
      puts "  Verifying key-based SSH access..."
      Net::SSH.start(target_ip, default_user,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        result = ssh.exec!("whoami").strip
        puts "  Verified: logged in as #{result}"
      end

      transition_to!("keyed")
      puts "  Host #{hostname || id} keyed successfully."
    end

    protected

    # Default key installation — works for most Linux hosts.
    # Override in subclasses that need special handling (e.g., read-only filesystem).
    def install_key(ssh, pub_key)
      ssh.exec!("mkdir -p ~/.ssh && chmod 700 ~/.ssh")
      ssh.exec!("echo '#{pub_key}' >> ~/.ssh/authorized_keys")
      ssh.exec!("chmod 600 ~/.ssh/authorized_keys")
    end
  end
end
