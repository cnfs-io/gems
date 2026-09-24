# frozen_string_literal: true

require_relative "pcs/version"

# Takes a site's bare-metal machines from "on the network" to "installed",
# from a control plane (a Raspberry Pi) on the site's LAN.
module Pcs
  class Error < StandardError; end
end

require "termino"
require "state_machines-activemodel"
require_relative "pcs/settings"
require_relative "pcs/adapters/system_cmd"
require_relative "pcs/adapters/ssh"
require_relative "pcs/adapters/nmap"
require_relative "pcs/adapters/pcm"
require_relative "pcs/adapters/download"
require_relative "pcs/adapters/probe"
require_relative "pcs/local"
require_relative "pcs/template"
require_relative "pcs/public_key"
require_relative "pcs/pxe_target"
require_relative "pcs/operations/scan"
require_relative "pcs/operations/reconcile"
require_relative "pcs/operations/host_operation"
require_relative "pcs/operations/key"
require_relative "pcs/operations/configure"
require_relative "pcs/operations/install"
require_relative "pcs/app"
