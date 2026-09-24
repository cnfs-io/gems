# frozen_string_literal: true

module Pcs
  module Commands
    # `pcs networks scan [NAME]`: records what answers on the site's networks.
    class Scan < Termino::Command
      desc "Find machines on the networks (nmap ping scan) and record them as hosts"
      argument :network, desc: "A network's name (default: every network)"
      option :dry_run, type: :boolean, default: false, desc: "Scan, but only list what would be recorded"

      def call(network: nil, dry_run: false, **)
        enter_project!
        run_operation Operations::Scan.new(networks: networks(network), dry_run:, out: $stdout)
      end

      private

      def networks(name)
        return Network.all.to_a unless name

        [Network.find_by(name:) || abort("Error: no network named #{name}")]
      end
    end
  end
end
