# frozen_string_literal: true

module Pim
  class BuildsView < RestCli::View
    columns       :id, :profile, :distro, :arch
    detail_fields :id, :profile, :iso, :distro, :automation, :build_method,
                  :arch, :target, :disk_size, :memory, :cpus

    field_prompt :profile,     :select, choices: ->(_) { Pim::Profile.all.map(&:id) }
    field_prompt :iso,         :select, choices: ->(_) { Pim::Iso.all.map(&:id) }
    field_prompt :arch,        :select, choices: %w[amd64 arm64]
    field_prompt :target,      :select, choices: ->(_) { Pim::Target.all.map(&:id) }
    field_prompt :distro,      :ask
    field_prompt :disk_size,   :ask
    field_prompt :memory,      :ask
    field_prompt :cpus,        :ask
    field_prompt :ssh_user,    :ask
    field_prompt :ssh_timeout, :ask
  end
end
