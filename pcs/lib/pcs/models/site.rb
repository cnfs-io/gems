# frozen_string_literal: true

module Pcs
  # The physical location this project manages. One project is one site.
  class Site < FlatRecord::Base
    file_layout :individual
    source "sites"

    attribute :name, :string
    attribute :domain, :string
    attribute :timezone, :string

    validates :name, :domain, :timezone, presence: true

    has_many :networks, class_name: "Pcs::Network", foreign_key: :site_id, dependent: :restrict_with_error
    has_many :hosts, class_name: "Pcs::Host", foreign_key: :site_id, dependent: :restrict_with_error

    def self.current
      first || raise(Pcs::Error, "this project has no site; create projects with `pcs new`")
    end
  end
end
