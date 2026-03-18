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

    validates :type, inclusion: {
      in: ->(_) { Host.valid_types },
      message: "%{value} is not a valid host type"
    }, allow_nil: true

    # --- Valid types from STI subclasses ---

    def self.valid_types
      sti_types.keys
    end

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

      after_transition to: :configured do |host|
        host.site&.reconcile!
      end
    end

    # --- Guards ---

    def ready_to_key?
      return false if blank?(connect_user)
      return false if blank?(connect_pass)
      return false unless interfaces.any? { |i| i.reachable_ip }
      true
    end

    # Verify key-based SSH access via agent.
    # target: symbol for which IP method to call on the interface (:reachable_ip, :configured_ip, :discovered_ip)
    def key_access?(target: :reachable_ip)
      iface = interfaces.first
      return false unless iface

      target_ip = iface.send(target)
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
      return false if interfaces.any? { |i| blank?(i.configured_ip) }
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

    # --- Config resolution (per-type defaults → global fallback) ---

    def wait_attempts
      host_default(:wait_attempts) || Pcs1.config.host.wait_attempts
    end

    def wait_interval
      host_default(:wait_interval) || Pcs1.config.host.wait_interval
    end

    # --- Local host detection ---

    def self.local_ips
      Platform.current.local_ips
    end

    def self.local
      local_ips.each do |ip|
        iface = Pcs1::Interface.find_by(configured_ip: ip) ||
                Pcs1::Interface.find_by(discovered_ip: ip)
        return iface.host if iface
      end
      nil
    end

    # --- Keying ---

    # Push the SSH public key to this host using default credentials.
    # Does NOT change status — fire_status_event(:key) after verifying with key_access?
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

    # --- Provisioning ---

    # Provision this host: restart networking to pick up DHCP reservation,
    # then verify reachability at configured IP.
    def provision!
      configured_ip = interfaces.first&.configured_ip
      raise "No configured IP — run 'host configure' first" unless configured_ip

      puts "  Restarting networking on #{hostname || id}..."
      restart_networking!

      puts "  Waiting for host to come back (#{wait_attempts} attempts, #{wait_interval}s interval)..."
      wait_for_host(configured_ip)

      if key_access?(target: :configured_ip)
        puts "  Verified: #{hostname || id} reachable at #{configured_ip}"
        fire_status_event(:provision)
        save!
        puts "  Host #{hostname || id} provisioned."
      else
        raise "Host #{hostname || id} not reachable at #{configured_ip} after restart"
      end
    end

    # Override in STI subclasses for host-specific restart behavior.
    def restart_networking!
      raise NotImplementedError, "#{self.class} must implement #restart_networking!"
    end

    protected

    # Default key installation — works for most Linux hosts.
    # Override in subclasses that need special handling (e.g., read-only filesystem).
    def install_key(ssh, pub_key)
      ssh.exec!("mkdir -p ~/.ssh && chmod 700 ~/.ssh")
      ssh.exec!("echo '#{pub_key}' >> ~/.ssh/authorized_keys")
      ssh.exec!("chmod 600 ~/.ssh/authorized_keys")
    end

    # SSH into the host at its current reachable IP and execute a command.
    def ssh_exec!(command)
      target_ip = interfaces.first&.reachable_ip
      raise "No reachable IP for host #{hostname || id}" unless target_ip

      user = connect_user
      raise "No connect_user for host #{hostname || id}" if blank?(user)

      Net::SSH.start(target_ip, user,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        ssh.exec!(command)
      end
    end

    # Wait for a host to become reachable at an IP (after reboot/restart).
    # Reads attempts/interval from per-type config or global config.
    def wait_for_host(ip)
      wait_attempts.times do |i|
        if tcp_port_open?(ip, 22)
          puts "  Host reachable at #{ip} (attempt #{i + 1}/#{wait_attempts})"
          return true
        end
        sleep wait_interval
      end
      raise "Host not reachable at #{ip} after #{wait_attempts * wait_interval}s"
    end

    private

    def tcp_port_open?(host, port, timeout: 3)
      Socket.tcp(host, port, connect_timeout: timeout) { true }
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, SocketError
      false
    end

    def host_default(field)
      defaults = Pcs1.config.host_defaults[type] || {}
      defaults[field]
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
