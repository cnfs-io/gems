# frozen_string_literal: true

module Pim
  class IsosView < RestCli::View
    columns       :id, :architecture, :name
    detail_fields :id, :name, :architecture, :url, :checksum, :checksum_url, :filename

    field_prompt :architecture, :select, choices: %w[amd64 arm64]
    field_prompt :name,         :ask
    field_prompt :url,          :ask
    field_prompt :checksum,     :ask
    field_prompt :checksum_url, :ask
    field_prompt :filename,     :ask
  end
end
