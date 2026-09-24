# frozen_string_literal: true

require "io/console"

module Pcs
  module Commands
    # `pcs hosts key|configure|install ID`: a host's operations, run in the
    # foreground (the web UI runs the same ones as jobs).
    module HostOperations
      # Shared: the host id argument and --dry-run.
      class Base < Termino::Command
        argument :id, required: true, desc: "Host id"
        option :dry_run, type: :boolean, default: false, desc: "Only list what would be done"

        def call(id:, dry_run: false, **options)
          enter_project!
          run_operation operation.new(host_id: id, dry_run:, out: $stdout, **extra(options))
        end

        private

        def extra(_options) = {}
      end

      # Key.
      class Key < Base
        desc "Put pcs's key on a device (a PiKVM) and check it logs in"
        option :password, type: :boolean, default: false,
                          desc: "Ask for the device's password to install the key (else it must be there already)"

        private

        def operation = Operations::Key

        def extra(options)
          return {} unless options[:password]

          { password: $stdin.getpass("Password for the device (not stored): ") }
        end
      end

      # Configure.
      class Configure < Base
        desc "Mark a host configured (once it has everything pcs needs) and write its boot files"

        private

        def operation = Operations::Configure
      end

      # Install.
      class Install < Base
        desc "Install Debian on a configured host over PXE (you PXE boot it when asked)"

        private

        def operation = Operations::Install
      end
    end
  end
end
