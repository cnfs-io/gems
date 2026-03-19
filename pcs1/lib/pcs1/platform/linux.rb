# frozen_string_literal: true

require "json"

module Pcs1
  module Platform
    class Linux
      def local_ips
        json = `ip -j addr show 2>/dev/null`
        return [] if json.empty?

        JSON.parse(json).flat_map do |iface|
          (iface["addr_info"] || [])
            .select { |a| a["family"] == "inet" && a["scope"] == "global" }
            .map { |a| a["local"] }
        end.compact
      end

      def available_timezones
        output = `timedatectl list-timezones 2>/dev/null`
        return ["UTC"] if output.empty?

        output.lines.map(&:strip)
      end
    end
  end
end
