# frozen_string_literal: true

module Pcs
  module Operations
    # Installs Debian on a configured host over PXE: configured -> provisioned.
    #
    #  1. Its boot menu is switched to install, and someone PXE boots it.
    #  2. When the installer's network is up (its address answers pings), the
    #     menu goes back to booting the disk, before the install reboots.
    #  3. When the installed system accepts pcs's key, the host is provisioned.
    #
    # If anything fails, the menu goes back to the disk: a host is never left
    # set to wipe itself on its next boot.
    class Install < HostOperation
      # A server stopped mid-install (see Termino::Job): back to the disk.
      def self.interrupted(host_id:)
        host = Host.find(host_id)
        return unless host.pxe_install

        host.update!(pxe_install: false)
        Reconcile.new.call!
      end

      def initialize(probe: Adapters::Probe.new, interval: 10, **)
        super(**)
        @probe = probe
        @interval = interval
      end

      private

      def perform
        check_ready!
        boot_installer
        wait_for_installer
        boot_disk
        wait_for_login
        step("mark #{host.name} provisioned") { host.provision! }
        host
      rescue StandardError, Interrupt
        restore_disk_boot
        raise
      end

      def restore_disk_boot
        return if dry_run? || !host.pxe_install

        boot_disk
      rescue StandardError => e
        log "✗ couldn't set #{host.name}'s boot menu back to its disk (#{e.message}): " \
            "run `pcs hosts update #{host.id} --no-pxe-install` and `pcs reconcile` before it reboots"
      end

      def check_ready!
        raise Pcs::Error, "pcs doesn't install #{host.name}'s type" unless host.pxe?
        raise Pcs::Error, "#{host.name} is #{host.status}; configure it first" unless host.can_provision?
      end

      def ip = host.primary_interface.configured_ip
      def timeout = @settings.install.timeout.to_f * 60

      def boot_installer
        step("set #{host.name}'s boot menu to install") { host.update!(pxe_install: true) }
        reconcile
        log "#{dry_run? ? "• would ask you to" : "Now"} PXE boot #{host.name} (power it on, or reboot it)" \
            "#{": its boot menu installs Debian." unless dry_run?}"
      end

      # Checks at least as often as the timeout allows.
      def interval = [@interval, timeout].min

      # If something already answers at the address (a reinstall), it must
      # go down first, or its answer would pass for the installer's.
      def wait_for_installer
        wait_for("#{ip} to go quiet (#{host.name} rebooting)", timeout:, interval:) { !up? } if up?
        wait_for("the installer to answer at #{ip}", timeout:, interval:) { up? }
      end

      def up? = @probe.ping?(ip)

      def boot_disk
        step("set #{host.name}'s boot menu back to its disk") { host.update!(pxe_install: false) }
        reconcile
      end

      # Its host key is new (it was just installed), so the pinned one goes.
      def wait_for_login
        step("forget #{ip}'s old SSH host key") { ssh.forget_host_key }
        wait_for("#{host.name} to accept pcs's key at #{ip}", timeout:, interval:) { ssh.reachable? }
      end
    end
  end
end
