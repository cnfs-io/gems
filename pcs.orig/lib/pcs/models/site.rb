# frozen_string_literal: true

require "yaml"

module Pcs
  class Site < FlatRecord::Base
    source "sites"
    class_attribute :top_level_domain, default: "local"

    def self.hierarchy_parent? = true

    TOP_FIELDS = %i[domain timezone ssh_key].freeze

    attribute :name, :string
    attribute :domain, :string
    attribute :timezone, :string
    attribute :ssh_key, :string

    has_many :hosts, class_name: "Pcs::Host", foreign_key: :site_id
    has_many :services, class_name: "Pcs::Service", foreign_key: :site_id
    has_many :networks, class_name: "Pcs::Network", foreign_key: :site_id

    after_initialize :load_site_yml

    def self.load(site_name = Pcs.site)
      find_by(name: site_name)
    end

    def ssh_key_path
      return nil unless ssh_key
      Pathname(ssh_key).expand_path
    end

    def ssh_private_key_path
      path = ssh_key_path
      return nil unless path
      path.extname == ".pub" ? path.sub_ext("") : path
    end

    def ssh_public_key_path
      path = ssh_key_path
      return nil unless path
      path.extname == ".pub" ? path : path.sub_ext(".pub")
    end

    def ssh_public_key_content
      pub = ssh_public_key_path
      pub&.exist? ? pub.read.strip : nil
    end

    def network(net_name)
      networks.find { |n| n.name == net_name.to_s }
    end

    def primary_network
      networks.find(&:primary)
    end

    def save!
      # Write site.yml directly (not through FlatRecord's store)
      data_path = Pathname.new(FlatRecord.configuration.data_path)
      path = data_path / name / "site.yml"
      path.dirname.mkpath

      out = {}
      out["domain"] = domain if domain
      out["timezone"] = timezone if timezone
      out["ssh_key"] = ssh_key if ssh_key

      path.write(YAML.dump(out))
      self
    end

    private

    def load_site_yml
      return unless name

      data_path = Pathname.new(FlatRecord.configuration.data_path)
      path = data_path / name / "site.yml"
      return unless path.exist?

      data = YAML.safe_load_file(path, symbolize_names: true) || {}

      self.domain = data[:domain] if data[:domain]
      self.timezone = data[:timezone] if data[:timezone]
      self.ssh_key = data[:ssh_key] if data[:ssh_key]

      clear_changes_information
    end
  end
end
