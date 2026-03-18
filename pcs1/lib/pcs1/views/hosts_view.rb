# frozen_string_literal: true

module Pcs1
  class HostsView < RestCli::View
    columns       :id, :hostname, :type, :role, :status
    detail_fields :id, :hostname, :type, :role, :arch, :status,
                  :connect_as, :site_id

    has_many :interfaces, columns: [:name, :discovered_ip, :ip, :mac, :network_id]

    field_prompt :hostname, :ask
    field_prompt :role,     :ask
    field_prompt :type,     :ask
    field_prompt :arch,     :select, choices: %w[amd64 arm64]
  end
end
