# frozen_string_literal: true

module Pcs
  # A JetKVM: its key is added by hand in its web UI.
  class JetkvmHost < Host
    sti_type "jetkvm"

    def self.label = "JetKVM"

    def ssh_user = "root"

    # JetKVM takes SSH keys only through its web UI (developer mode).
    def key_install_command(_public_key) = nil
  end
end
