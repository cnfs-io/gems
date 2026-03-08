# frozen_string_literal: true

module Pim
  class TargetsView < RestCli::View
    columns       :id, :type, :name
    detail_fields :id, :type, :name, :parent_id

    field_prompt :type,      :select, choices: %w[local proxmox aws iso]
    field_prompt :parent_id, :select, choices: ->(_) { Pim::Target.all.map(&:id) }
    field_prompt :name,      :ask
  end
end
