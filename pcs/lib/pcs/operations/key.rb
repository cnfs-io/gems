# frozen_string_literal: true

module Pcs
  module Operations
    # Puts pcs's key on a device that comes with its own OS (a PiKVM), then
    # checks pcs can log in with it: discovered -> keyed.
    #
    # With password (the device's own, used once and never stored), pcs
    # installs the key itself; without, the key must already be there (added
    # in the device's web UI, as a JetKVM needs).
    class Key < HostOperation
      def initialize(password: nil, **)
        super(**)
        @password = password
      end

      private

      def perform
        check_keyable!
        install_key if @password
        step("log in to #{host.name} as #{host.ssh_user} with pcs's key") { ssh.run!("true") }
        step("mark #{host.name} keyed") { host.key! }
        host
      end

      def check_keyable!
        raise Pcs::Error, "#{host.name} gets pcs's key from its install; configure it instead" unless host.requires_key?
        raise Pcs::Error, "#{host.name} is #{host.status}; only discovered hosts are keyed" unless host.can_key?
      end

      def install_key
        command = host.key_install_command(public_key) ||
                  raise(Pcs::Error, "add pcs's key in #{host.name}'s web UI, then key it without a password")
        step("install pcs's key on #{host.name} as #{host.ssh_user}") { ssh(password: @password).run!(*command) }
      end
    end
  end
end
