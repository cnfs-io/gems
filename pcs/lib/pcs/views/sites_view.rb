# frozen_string_literal: true

module Pcs
  class SitesView < RestCli::View
    columns       :name, :domain
    detail_fields :name, :domain, :timezone, :ssh_key

    has_many :networks, columns: [:name, :subnet, :gateway, :primary]

    field_prompt :domain,   :ask
    field_prompt :timezone, :select,
      choices: ->(_) { Platform.current.available_timezones(Adapters::SystemCmd.new) },
      filter: true
    field_prompt :ssh_key,  :ask
  end
end
