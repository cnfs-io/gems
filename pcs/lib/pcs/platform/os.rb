# frozen_string_literal: true

require "yaml"
require "pathname"

module Pcs
  module Platform
    module Os
      YAML_PATH = Pathname.new(__dir__).join("operating_systems.yml").freeze

      class << self
        def config_for(os_name)
          configs.fetch(os_name.to_sym) { raise "Unknown OS: #{os_name}. Available: #{configs.keys.join(", ")}" }
        end

        def configs
          @configs ||= YAML.safe_load_file(YAML_PATH, symbolize_names: true)
        end

        def available
          configs.keys.map(&:to_s)
        end

        # Returns firmware URL for an OS, or nil if not set
        def firmware_url(os_name)
          os = config_for(os_name)
          os[:firmware_url]
        end

        # Returns { kernel_path:, initrd_path: } for a specific arch
        def installer_for(os_name, arch)
          os = config_for(os_name)
          installers = os[:installer] || {}
          arch_key = arch.to_sym

          unless installers.key?(arch_key)
            raise "OS '#{os_name}' has no installer for arch '#{arch}'. Available: #{installers.keys.join(", ")}"
          end

          installers[arch_key]
        end

        # Compose full URLs for kernel and initrd
        def installer_urls(os_name, arch)
          os = config_for(os_name)
          paths = installer_for(os_name, arch)
          mirror = os[:mirror]

          {
            kernel_url: "#{mirror}/#{paths[:kernel_path]}",
            initrd_url: "#{mirror}/#{paths[:initrd_path]}"
          }
        end

        def reset!
          @configs = nil
        end
      end
    end
  end
end
