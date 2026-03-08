# frozen_string_literal: true

require "time"

module Pcs
  class Host < FlatRecord::Base
    source "hosts"
    sti_column :type

    FIELDS = %i[id mac discovered_ip compute_ip storage_ip hostname connect_as
                type role arch status preseed_interface discovered_at last_seen_at].freeze
    MUTABLE_FIELDS = %i[compute_ip storage_ip hostname connect_as type role arch status].freeze

    attribute :mac, :string
    attribute :discovered_ip, :string
    attribute :compute_ip, :string
    attribute :storage_ip, :string
    attribute :hostname, :string
    attribute :connect_as, :string, default: "root"
    attribute :type, :string
    attribute :role, :string
    attribute :arch, :string
    attribute :status, :string, default: "discovered"
    attribute :preseed_interface, :string
    attribute :preseed_device, :string
    attribute :discovered_at, :string
    attribute :last_seen_at, :string
    attribute :site_id, :string

    belongs_to :site, class_name: "Pcs::Site"
    has_many :interfaces, class_name: "Pcs::Interface", foreign_key: :host_id

    # --- Class-level query methods ---

    def self.load(site_name = Pcs.site)
      where(site_id: site_name)
    end

    def self.find_by_mac(mac, site_name: nil)
      scope = site_name ? where(site_id: site_name) : all
      normalized = mac&.downcase
      scope.detect { |d| d.mac&.downcase == normalized }
    end

    def self.find_by_ip(ip, site_name: nil)
      attrs = { discovered_ip: ip }
      attrs[:site_id] = site_name if site_name
      find_by(attrs)
    end

    def self.hosts_of_type(type, site_name: Pcs.site)
      where(type: type.to_s, site_id: site_name)
    end

    def self.merge_scan(site_name, scan_results, network: nil)
      counts = { new: 0, updated: 0, unchanged: 0 }

      scan_results.each do |result|
        ip = result[:ip]
        mac = result[:mac]

        existing = if mac && network
                     find_by_mac_via_interface(mac, site_name: site_name) ||
                       find_by_mac(mac, site_name: site_name)
                   elsif mac
                     find_by_mac(mac, site_name: site_name)
                   else
                     find_by_ip(ip, site_name: site_name)
                   end

        if existing
          existing.update(last_seen_at: Time.now.iso8601)

          if network
            iface = existing.interface_on(network.name)
            if iface
              iface.update(ip: ip, mac: mac) if iface.ip != ip
              counts[:unchanged] += 1
            else
              Interface.create(
                mac: mac, ip: ip,
                host_id: existing.id, network_id: network.id,
                site_id: site_name
              )
              counts[:updated] += 1
            end
          else
            if existing.discovered_ip != ip
              existing.update(discovered_ip: ip)
              counts[:updated] += 1
            else
              counts[:unchanged] += 1
            end
          end
        else
          host = create(
            mac: mac,
            discovered_ip: ip,
            site_id: site_name,
            status: "discovered",
            connect_as: "root",
            discovered_at: Time.now.iso8601,
            last_seen_at: Time.now.iso8601
          )

          if network
            Interface.create(
              mac: mac, ip: ip,
              host_id: host.id, network_id: network.id,
              site_id: site_name
            )
          end

          counts[:new] += 1
        end
      end

      counts
    end

    def self.find_by_mac_via_interface(mac, site_name:)
      return nil unless mac
      normalized = mac.downcase
      iface = Interface.load(site_name).detect { |i| i.mac&.downcase == normalized }
      iface&.host
    end

    # --- Strategy methods (overridden by STI subclasses) ---

    def self.detect?(ssh_session)
      raise NotImplementedError
    end

    def render(output_dir)
      raise NotImplementedError
    end

    def deploy!(output_dir, state:)
      raise NotImplementedError
    end

    def configure!
      raise NotImplementedError
    end

    def healthy?
      raise NotImplementedError
    end

    # --- Convenience helpers (site accessed via association) ---

    def fqdn
      "#{hostname}.#{site.domain}"
    end

    def has_storage?
      !interface_on(:storage).nil?
    end

    def compute_network
      site.network(:compute)
    end

    def storage_network
      site.network(:storage)
    end

    # --- Interface convenience methods ---

    def primary_interface
      return nil if interfaces.none?
      interfaces.detect { |i| i.network&.primary } || interfaces.first
    end

    def interface_on(network_name)
      interfaces.detect { |i| i.network&.name == network_name.to_s }
    end

    def ip_on(network_name)
      interface_on(network_name)&.ip
    end

    def interface_name
      primary_interface&.name
    end

    protected

    def with_ssh(ip = nil, user: "root", state:, &block)
      target_ip = ip || current_ip(state: state)
      Pcs::Adapters::SSH.connect(host: target_ip, key: site.ssh_private_key_path, user: user, &block)
    end

    def with_ssh_probe(ip = nil, state:, &block)
      target_ip = ip || current_ip(state: state)
      result = Pcs::Adapters::SSH.probe(host: target_ip, &block)
      raise "Could not authenticate to #{target_ip}" unless result
      result
    end

    def write_local(output_dir, path, content)
      dest = output_dir / path.delete_prefix("/")
      dest.dirname.mkpath
      dest.write(content)
      puts "  -> #{dest}"
    end

    def current_ip(state:)
      host_status = state.host_status(hostname)
      case host_status
      when "discovered", "installing"
        discovered_ip
      else
        ip_on(:compute) || discovered_ip
      end
    end
  end
end
