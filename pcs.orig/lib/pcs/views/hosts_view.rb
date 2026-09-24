# frozen_string_literal: true

module Pcs
  class HostsView < RestCli::View
    columns       :id, :hostname, :type, :role, :status
    detail_fields :id, :hostname, :type, :role, :arch, :status,
                  :connect_as, :discovered_ip, :preseed_device,
                  :discovered_at, :last_seen_at

    has_many :interfaces, columns: [:name, :network_name, :ip, :mac]

    field_prompt :role, :select, choices: ->(_) { Pcs::Role.names }
    field_prompt :type, :select, choices: ->(host) { Pcs::Role.types_for(host.role) }
    field_prompt :arch, :select, choices: %w[amd64 arm64]
    field_prompt :hostname, :ask
  end
end
