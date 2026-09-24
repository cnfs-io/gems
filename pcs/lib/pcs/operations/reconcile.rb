# frozen_string_literal: true

require "uri"
require_relative "reconcile/files"
require_relative "reconcile/installers"

module Pcs
  module Operations
    # Makes the netboot services match the data: renders the dnsmasq config,
    # each installable host's boot menu, preseed and post-install hook, and
    # fetches the installers the hosts need. Writes only files whose content
    # changed, removes files for hosts that are gone, and restarts dnsmasq
    # only if its config changed. Returns the hosts that can PXE install.
    class Reconcile < Termino::Operation
      include Files
      include Installers

      USER = /\A[a-z_][a-z0-9_-]{0,31}\z/
      PASSWORD_HASH = %r{\A\$6\$[^$\s]+\$[./0-9A-Za-z]+\z}

      def initialize(settings: Pcs.settings, pcm: Adapters::Pcm.new, download: Adapters::Download.new, **)
        super(**)
        @settings = settings
        @pcm = pcm
        @download = download
      end

      private

      def perform
        check_install_settings!
        targets = PxeTarget.all(settings: @settings)
        dnsmasq_changed = write(dnsmasq_path, dnsmasq_config)
        targets.each { |target| write_host_files(target) }
        remove_stale(targets)
        fetch_installers(targets)
        restart_dnsmasq if dnsmasq_changed
        targets
      end

      def check_install_settings!
        install = @settings.install
        unless install.user.to_s.match?(USER)
          raise Pcs::Error,
                "install.user #{install.user.inspect} isn't a valid user name"
        end
        return if install.password_hash.nil? || install.password_hash.match?(PASSWORD_HASH)

        raise Pcs::Error, "install.password_hash must be a SHA-512 crypt hash (mkpasswd -m sha-512), never a password"
      end

      # --- dnsmasq -------------------------------------------------------

      def dnsmasq_path
        File.join(@settings.dnsmasq.config_dir, "pcs.conf")
      end

      def dnsmasq_config
        mode = @settings.dnsmasq.mode
        raise Pcs::Error, "dnsmasq.mode must be proxy or dhcp, not #{mode.inspect}" unless %w[proxy dhcp].include?(mode)

        networks = Network.all.select(&:control_plane_ip)
        raise Pcs::Error, "the control plane has no configured address on any network" if networks.empty?

        check_dhcp_ranges!(networks) if mode == "dhcp"
        Template.render("dnsmasq.conf", site: Site.current, mode:, networks:, reservations: reservations(networks))
      end

      def check_dhcp_ranges!(networks)
        missing = networks.select { |n| n.dhcp_start.blank? || n.dhcp_end.blank? || n.gateway.blank? }
        return if missing.empty?

        raise Pcs::Error, "dhcp mode needs a gateway, dhcp start and dhcp end on #{missing.map(&:name).join(", ")}"
      end

      # Configured hosts' interfaces on the networks dnsmasq serves.
      def reservations(networks)
        ids = networks.map(&:id)
        Interface.all.select do |iface|
          ids.include?(iface.network_id) && iface.mac.present? && iface.configured_ip.present? &&
            iface.host&.hostname.present?
        end
      end

      def restart_dnsmasq
        service = @settings.dnsmasq.service
        return log("dnsmasq isn't running; start it with `pcs service start #{service}`") unless @pcm.running?(service)

        step("restart #{service}") { @pcm.restart(service) }
      end

      # --- per host ------------------------------------------------------

      def write_host_files(target)
        locals = host_locals(target)
        write(menu_path(target), Template.render("boot-menu.ipxe", **locals, timeout_ms:))
        write(asset_path(target.preseed_file), Template.render("preseed.cfg", **locals, mirror:, public_key:))
        write(asset_path(target.post_install_file), Template.render("post-install.sh", **locals))
      end

      def host_locals(target)
        { target:, host: target.host, interface: target.interface, install: @settings.install }
      end

      def menu_path(target) = File.join(@settings.netboot.menus_dir, target.menu_file)
      def asset_path(file) = File.join(@settings.netboot.assets_dir, file)
      def timeout_ms = (@settings.netboot.menu_timeout.to_f * 1000).to_i
      def mirror = URI(@settings.install.mirror)

      def public_key
        @public_key ||= PublicKey.read(@settings.ssh.key_path)
      end
    end
  end
end
