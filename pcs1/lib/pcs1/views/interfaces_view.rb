# frozen_string_literal: true

module Pcs1
  class InterfacesView < RestCli::View
    columns       :id, :name, :discovered_ip, :ip, :mac, :host_id, :network_id
    detail_fields :id, :name, :discovered_ip, :ip, :mac, :host_id, :network_id

    field_prompt :name, :ask
    field_prompt :discovered_ip, :ask
    field_prompt :ip,   :ask
    field_prompt :mac,  :ask
  end
end
