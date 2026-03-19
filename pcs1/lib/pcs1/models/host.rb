# frozen_string_literal: true

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
    attribute :pxe_boot, :boolean, default: false
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

    # --- Identity ---

    def local?
      local_ips = self.class.local_ips
      interfaces.any? { |i| local_ips.include?(i.configured_ip) || local_ips.include?(i.discovered_ip) }
    end

    # --- PXE ---

    def pxe_target?
      pxe_boot && !local? && !boot_menu_entry.nil?
    end

    # --- Guards ---

    def ready_to_key?
      return false if blank?(connect_user)
      return false if blank?(connect_pass)
      return false unless interfaces.any? { |i| i.reachable_ip }
      true
    end

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

    # --- Install file generation (PXE/preseed) ---

    def generate_install_files(_output_dir)
      nil
    end

    def kernel_params(base_url:)
      nil
    end

    def boot_menu_entry
      nil
    end

    # --- Keying ---

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

      Pcs1.logger.info("Pushing SSH key to #{target_ip} as #{connect_user}...")
      Net::SSH.start(target_ip, connect_user,
                     password: connect_pass,
                     non_interactive: true,
                     verify_host_key: :never,
                     timeout: 10) do |ssh|
        install_key(ssh, pub_key)
      end
      Pcs1.logger.info("Key pushed.")
    end

    # --- Provisioning ---

    def provision!
      configured_ip = interfaces.first&.configured_ip
      raise "No configured IP — run 'host configure' first" unless configured_ip

      Pcs1.logger.info("Restarting networking on #{hostname || id}...")
      restart_networking!

      Pcs1.logger.info("Waiting for host to come back (#{wait_attempts} attempts, #{wait_interval}s interval)...")
      wait_for_host(configured_ip)

      if key_access?(target: :configured_ip)
        Pcs1.logger.info("Verified: #{hostname || id} reachable at #{configured_ip}")
        fire_status_event(:provision)
        save!
        Pcs1.logger.info("Host #{hostname || id} provisioned.")
      else
        raise "Host #{hostname || id} not reachable at #{configured_ip} after restart"
      end
    end

    def restart_networking!
      raise NotImplementedError, "#{self.class} must implement #restart_networking!"
    end

    protected

    def install_key(ssh, pub_key)
      ssh.exec!("mkdir -p ~/.ssh && chmod 700 ~/.ssh")
      ssh.exec!("echo '#{pub_key}' >> ~/.ssh/authorized_keys")
      ssh.exec!("chmod 600 ~/.ssh/authorized_keys")
    end

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

    def wait_for_host(ip)
      wait_attempts.times do |i|
        if tcp_port_open?(ip, 22)
          Pcs1.logger.info("Host reachable at #{ip} (attempt #{i + 1}/#{wait_attempts})")
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
