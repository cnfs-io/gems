# frozen_string_literal: true

require "yaml"
require "pathname"

module Pcs
  module Platform
    module Arch
      YAML_PATH = Pathname.new(__dir__).join("architectures.yml").freeze
      SUPPORTED = %w[amd64 arm64].freeze

      class << self
        def config_for(arch)
          configs.fetch(arch.to_sym) { raise "Unsupported architecture: #{arch}. Supported: #{SUPPORTED.join(", ")}" }
        end

        def configs
          @configs ||= YAML.safe_load_file(YAML_PATH, symbolize_names: true)
        end

        def native
          case RUBY_PLATFORM
          when /aarch64|arm64/ then "arm64"
          when /x86_64|x64/    then "amd64"
          else raise "Unknown host architecture: #{RUBY_PLATFORM}"
          end
        end

        def resolve(requested)
          return native if requested.nil? || requested.empty?
          raise "Unsupported architecture: #{requested}" unless SUPPORTED.include?(requested)

          requested
        end

        def kvm_available?(arch)
          File.exist?("/dev/kvm") && arch == native
        end

        def verify_dependencies!(arch)
          cfg = config_for(arch)

          unless system("command -v #{cfg[:qemu_binary]} > /dev/null 2>&1")
            raise "#{cfg[:qemu_binary]} not found. Install the appropriate qemu-system package."
          end

          if cfg[:uefi_firmware] && !File.exist?(cfg[:uefi_firmware])
            raise "UEFI firmware not found at #{cfg[:uefi_firmware]}. Install with: sudo apt-get install -y qemu-efi-aarch64"
          end
        end

        def reset!
          @configs = nil
        end
      end
    end
  end
end
