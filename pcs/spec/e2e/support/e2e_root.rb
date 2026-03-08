# frozen_string_literal: true

require "pathname"

module Pcs
  module E2E
    E2E_ROOT = Pathname.new("/tmp/pcs-e2e")

    # Subdirectory paths — all under E2E_ROOT
    DIRS = {
      project:  E2E_ROOT / "project",
      netboot:  E2E_ROOT / "netboot",
      disk:     E2E_ROOT / "disk",
      logs:     E2E_ROOT / "logs",
      ssh:      E2E_ROOT / "project" / ".ssh"
    }.freeze

    def self.setup_dirs!
      DIRS.each_value(&:mkpath)
    end

    def self.cleanup!
      E2E_ROOT.rmtree if E2E_ROOT.exist?
    end
  end
end
