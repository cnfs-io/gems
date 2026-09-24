# frozen_string_literal: true

module Pcs
  # A Debian host that becomes a Proxmox VE node (the upgrade comes later).
  class PveHost < DebianHost
    sti_type "proxmox"

    def self.label = "Proxmox VE"
  end
end
