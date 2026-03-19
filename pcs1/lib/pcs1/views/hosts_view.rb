# frozen_string_literal: true

module Pcs1
  class HostsView < RestCli::View
    columns       :id, :hostname, :type, :role, :status, :pxe_boot
    detail_fields :id, :hostname, :type, :role, :arch, :status,
                  :pxe_boot, :connect_as, :site_id

    has_many :interfaces, columns: %i[name discovered_ip configured_ip mac network_id]

    field_prompt :hostname, :ask
    field_prompt :role,     :ask
    field_prompt :type,     :select, choices: ->(_) { Pcs1::Host.valid_types }
    field_prompt :arch,     :select, choices: %w[amd64 arm64]
  end
end
