# frozen_string_literal: true

module Pcs
  module Adapters
    # Controls the site's containers (dnsmasq, netboot) through pcm, which runs
    # the compose definitions the pcs ppm package installs. pcs never runs
    # podman or systemd itself.
    class Pcm
      def initialize(system: SystemCmd.new, bin: "pcm")
        @system = system
        @bin = bin
      end

      # Whether pcm knows the service (the ppm package installed its definition).
      def installed?(service)
        run("path", service).success?
      end

      def up(service) = run!("up", service)
      def down(service) = run!("down", service)
      def validate(service) = run("validate", service)

      # pcm has no restart or logs command yet; its compose passthrough does both.
      def restart(service) = run!("__compose", "restart", service)

      def logs(service, lines: 100)
        run("__compose", "logs", "--tail", lines, service).stdout
      end

      def running?(service)
        result = run("ps", "--filter", "label=com.docker.compose.project=#{service}", "--format", "{{.Names}}")
        result.success? && !result.stdout.strip.empty?
      end

      private

      def run(*args) = @system.run(@bin, *args)
      def run!(*args) = @system.run!(@bin, *args)
    end
  end
end
