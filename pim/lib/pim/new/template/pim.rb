# PIM Project Configuration
#
# This file is loaded when PIM boots. It configures PIM and its dependencies.
# Everything below the configure block is regular Ruby — set per-model
# overrides, require additional files, etc.

Pim.configure do |config|
  # Where ISOs are cached (default: ~/.cache/pim/isos)
  # config.iso_dir = "~/.cache/pim/isos"

  # Where built images are stored (default: ~/.local/share/pim/images)
  # config.image_dir = "~/.local/share/pim/images"

  # Preseed server defaults
  # config.serve_port = 8080

  # FlatRecord configuration
  config.flat_record do |fr|
    fr.backend = :yaml
    fr.id_strategy = :string
  end

  # `pim vm run` defaults (user-wide defaults can also go in ~/.config/pim/pim.rb)
  # config.vm do |vm|
  #   vm.disk = "clone"          # clone | overlay | snapshot
  #   vm.network = "bridged"     # bridged | host
  #   vm.bridge = "en0"          # interface to bridge (default: default-route interface)
  #   vm.usb = ["058f:6387"]     # USB disks to pass through: VID:PID or device path
  # end
end

# Per-model data path overrides (optional)
#
# By default, all models read from <project>/data/<source>/
# To share data with other tools (e.g., PCS), set a model's data_paths:
#
# Pim::Profile.data_paths = [Pim.root.join("../share/profiles")]
#
# To merge shared + project-local data (shared first, project overrides):
#
# Pim::Profile.data_paths = [
#   Pim.root.join("../share/profiles"),
#   Pim.root.join("data/profiles")
# ]
