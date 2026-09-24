# frozen_string_literal: true

module Pcs
  # A PiKVM: keyed over SSH (its root filesystem is read-only until remounted).
  class PikvmHost < Host
    sti_type "pikvm"

    def self.label = "PiKVM"

    def ssh_user = "root"

    # PiKVM's root filesystem is read-only; open it for the change.
    def key_install_command(public_key)
      ["sh", "-c", "rw && #{KEY_INSTALL}; status=$?; ro; exit $status", "key", public_key]
    end
  end
end
