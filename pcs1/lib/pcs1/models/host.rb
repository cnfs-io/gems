# frozen_string_literal: true

require "net/ssh"
require "state_machines-activemodel"

module Pcs1
  class Host < FlatRecord::Base
    source "hosts"
    sti_column :type

    attribute :hostname, :string
    attribute :role, :string
    attribute :type, :string
    attribute :arch, :string
    attribute :status, :string, default: "discovered"
    attribute :connect_as, :string
    attribute :connect_password, :string
    attribute :site_id, :string

    belongs_to :site, class_name: "Pcs1::Site"
    has_many :interfaces, class_name: "Pcs1::Interface", foreign_key: :host_id

    # --- Valid types from STI subclasses ---

    def self.valid_types
      sti_types.keys
    end

    validates :type, inclusion: {
      in: ->(_) { Host.valid_types },
      message: "%{value} is not a valid host type (valid: #{-> { Host.valid_types.join(", ") }.call})"
    }, allow_nil: true

    # --- State machine ---

    state_machine :status, initial: :discovered do
      state :discovered
      state :keyed
      state :configured
      state :provisioned

      event :key do
        transition discovered: :keyed, if: :key_access?
      end

      event :configure do
        transition keyed: :configured, if: :configuration_complete?
      end

      event :provision do
        transition configured: :provisioned
      end
    end

    # --- Guards ---

    def ready_to_key?
      return false if blank?(connect_user)
      return false if blank?(connect_pass)
      return false unless interfaces.any? { |i| i.reachable_ip }
      true
    end

    # Verify key-based SSH access via agent — can we log in without a password?
    def key_access?
      target_ip = interfaces.first&.reachable_ip
      return false unless target_ip

      user = connect_user
      return false if blank?(user)

      Net::SSH.start(target_ip, user,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        result = ssh.exec!("whoami")
        !result.nil? && !result.strip.empty?
      end
    rescue Net::SSH::AuthenticationFailed, Net::SSH::ConnectionTimeout,
           Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
      false
    end

    def configuration_complete?
      return false if blank?(hostname)
      return false if blank?(role)
      return false if blank?(type)
      return false if blank?(arch)
      return false unless interfaces.any?
      return false if interfaces.any? { |i| blank?(i.ip) }
      return false if interfaces.any? { |i| blank?(i.name) }
      true
    end

    # --- Credential resolution ---

    def connect_user
      connect_as || host_default(:user)
    end

    def connect_pass
      connect_password || host_default(:password)
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

    # Push the SSH public key to this host using default credentials.
    # Does NOT change status — call fire_status_event(:key) after verifying with key_access?
    def key!
      unless ready_to_key?
        missing = []
        missing << "connect_user" if blank?(connect_user)
        missing << "connect_password" if blank?(connect_pass)
        missing << "reachable interface" unless interfaces.any? { |i| i.reachable_ip }
        raise "Cannot key host #{hostname || id}: missing #{missing.join(", ")}"
      end

      pub_key = site.ssh_public_key_content
      raise "No SSH public key found at #{site.ssh_key}" unless pub_key

      target_ip = interfaces.first.reachable_ip

      puts "  Pushing SSH key to #{target_ip} as #{connect_user}..."
      Net::SSH.start(target_ip, connect_user,
                     password: connect_pass,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        install_key(ssh, pub_key)
      end
      puts "  Key pushed."
    end

    protected

    # Default key installation — works for most Linux hosts.
    # Override in subclasses that need special handling (e.g., read-only filesystem).
    def install_key(ssh, pub_key)
      ssh.exec!("mkdir -p ~/.ssh && chmod 700 ~/.ssh")
      ssh.exec!("echo '#{pub_key}' >> ~/.ssh/authorized_keys")
      ssh.exec!("chmod 600 ~/.ssh/authorized_keys")
    end

    private

    def host_default(field)
      defaults = Pcs1.config.host_defaults[type] || {}
      defaults[field]
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
