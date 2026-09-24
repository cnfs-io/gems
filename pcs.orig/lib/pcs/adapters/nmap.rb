# frozen_string_literal: true

require "json"

module Pcs
  module Adapters
    class Nmap
      def initialize(system_cmd: SystemCmd.new)
        @system_cmd = system_cmd
      end

      # Ping scan a subnet, return array of { ip:, mac: }
      def scan(subnet)
        result = @system_cmd.run!("nmap -sn #{subnet} -oX -", sudo: true)
        parse_xml(result.stdout)
      end

      private

      def parse_xml(xml_output)
        require "rexml/document"
        doc = REXML::Document.new(xml_output)

        hosts = []
        doc.elements.each("nmaprun/host") do |host_el|
          status = host_el.elements["status"]&.attributes&.[]("state")
          next unless status == "up"

          ip = host_el.elements["address[@addrtype='ipv4']"]&.attributes&.[]("addr")
          mac = host_el.elements["address[@addrtype='mac']"]&.attributes&.[]("addr")

          hosts << { ip: ip, mac: mac&.downcase } if ip
        end

        hosts
      end
    end
  end
end
