# frozen_string_literal: true

module Pim
  class ProfilesView < RestCli::View
    columns       :id, :hostname, :username
    detail_fields :id, :hostname, :username, :fullname, :timezone, :domain,
                  :locale, :keyboard, :packages

    field_prompt :parent_id,   :select, choices: ->(_) { Pim::Profile.all.map(&:id) }
    field_prompt :hostname,    :ask
    field_prompt :username,    :ask
    field_prompt :fullname,    :ask
    field_prompt :timezone,    :ask
    field_prompt :domain,      :ask
    field_prompt :locale,      :ask
    field_prompt :keyboard,    :ask
    field_prompt :packages,    :ask
  end
end
