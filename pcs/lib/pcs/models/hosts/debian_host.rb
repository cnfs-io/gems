# frozen_string_literal: true

module Pcs
  # A machine pcs installs Debian on over PXE.
  class DebianHost < Host
    sti_type "debian"

    attribute :disk, :string # the install target, e.g. /dev/sda or /dev/nvme0n1

    validates :disk, format: { with: %r{\A/dev/[\w/.-]+\z}, message: "must be a device path like /dev/sda" },
                     allow_blank: true

    # The PXE install puts pcs's key on it.
    def requires_key?
      false
    end

    def pxe?
      true
    end

    # Besides the basics: a disk to install on, and a network to install over
    # (with a gateway, and the control plane on it to serve the install).
    def missing_configuration
      network = primary_interface&.network
      super + {
        disk: disk,
        gateway: network&.gateway,
        control_plane_ip: network&.control_plane_ip
      }.select { |_, value| value.blank? }.keys
    end
  end
end
