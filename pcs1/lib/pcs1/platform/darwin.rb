# frozen_string_literal: true

require "pathname"

module Pcs1
  module Platform
    class Darwin
      def local_ips
        output = `ifconfig 2>/dev/null`
        return [] if output.empty?

        output.scan(/inet\s+(\d+\.\d+\.\d+\.\d+)/)
              .flatten
              .reject { |ip| ip == "127.0.0.1" }
      end

      def available_timezones
        dir = Pathname.new("/usr/share/zoneinfo")
        return ["UTC"] unless dir.exist?

        dir.glob("**/*")
           .select(&:file?)
           .map { |p| p.relative_path_from(dir).to_s }
           .reject { |z| z.start_with?("+VERSION", "posix", "right") }
           .sort
      end
    end
  end
end
