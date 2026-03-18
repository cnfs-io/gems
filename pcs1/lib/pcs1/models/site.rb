# frozen_string_literal: true

require "pathname"

module Pcs1
  class Site < FlatRecord::Base
    source "sites"

    attribute :name, :string
    attribute :domain, :string
    attribute :timezone, :string
    attribute :ssh_key, :string

    has_many :hosts, class_name: "Pcs1::Host", foreign_key: :site_id
    has_many :networks, class_name: "Pcs1::Network", foreign_key: :site_id

    def ssh_public_key_content
      return nil unless ssh_key
      path = Pathname(ssh_key).expand_path
      path.exist? ? path.read.strip : nil
    end

    # Called when a host transitions to configured.
    # Delegates to services to reconcile their state.
    def reconcile!
      Dnsmasq.reconcile!(exclude_ips: Host.local_ips)
    end
  end
end
