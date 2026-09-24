# frozen_string_literal: true

module Pcs
  module Operations
    # Shared by the operations that act on one host (Key, Configure, Install):
    # finding it, reaching it over SSH, and re-rendering the netboot files.
    class HostOperation < Termino::Operation
      # ssh: builds an Adapters::Ssh (tests pass a fake); reconcile: options
      # for the Reconcile runs (pcm:, download:).
      def initialize(host_id:, settings: Pcs.settings, ssh: nil, reconcile: {}, **)
        super(**)
        @host_id = host_id
        @settings = settings
        @ssh = ssh || method(:connect)
        @reconcile = reconcile
      end

      private

      def host
        @host ||= Host.find(@host_id)
      end

      def ssh(password: nil)
        @ssh.call(host, password:)
      end

      def connect(host, password: nil)
        ip = host.primary_interface&.reachable_ip || raise(Pcs::Error, "#{host.name} has no address")
        Adapters::Ssh.new(host: ip, user: host.ssh_user, key_path: @settings.ssh.key_path,
                          known_hosts: @settings.ssh.known_hosts, password:)
      end

      # Brings the netboot files up to date (as its own narrated operation).
      def reconcile
        op = Reconcile.new(settings: @settings, dry_run: dry_run?, out:, **@reconcile).call!
        @steps.concat(op.steps)
      end

      def public_key
        PublicKey.read(@settings.ssh.key_path)
      end
    end
  end
end
