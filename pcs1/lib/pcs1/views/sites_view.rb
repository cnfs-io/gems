# frozen_string_literal: true

module Pcs1
  class SitesView < RestCli::View
    columns       :id, :name, :domain
    detail_fields :id, :name, :domain, :timezone, :ssh_key

    field_prompt :name,     :ask
    field_prompt :domain,   :ask
    field_prompt :timezone, :select,
      choices: ->(_) { Pcs1::Platform.current.available_timezones },
      filter: true
    field_prompt :ssh_key,  :ask, default: "~/.ssh/id_ed25519"
  end
end
