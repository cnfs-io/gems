# frozen_string_literal: true

module Pcs
  module Commands
    # `pcs reconcile`: brings the netboot services' files up to date with the data.
    class Reconcile < Termino::Command
      desc "Write the dnsmasq config and each host's boot menu and preseed, and fetch installers"
      option :dry_run, type: :boolean, default: false, desc: "Only list what would change"

      def call(dry_run: false, **)
        enter_project!
        op = run_operation Operations::Reconcile.new(dry_run:, out: $stdout)
        puts "Nothing to change" if op.steps.empty?
        puts "#{op.value.size} host(s) can PXE install" unless dry_run
      end
    end
  end
end
