# frozen_string_literal: true

require_relative "platform"

module Pcs
  module NetworkDetect
    # Detect the local subnet from the primary network interface.
    # Returns a CIDR string like "10.0.10.0/24".
    def self.local_subnet(system_cmd: Adapters::SystemCmd.new)
      Platform.current.local_subnet(system_cmd)
    end
  end
end
