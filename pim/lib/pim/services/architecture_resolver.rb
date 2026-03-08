# frozen_string_literal: true

module Pim
  # Detect and route architecture to appropriate builder
  class ArchitectureResolver
    ARCH_MAP = {
      'arm64' => 'arm64',
      'aarch64' => 'arm64',
      'x86_64' => 'x86_64',
      'amd64' => 'x86_64'
    }.freeze

    def initialize; end

    def host_arch
      raw = `uname -m`.strip.downcase
      ARCH_MAP[raw] || raw
    end

    def normalize(arch)
      ARCH_MAP[arch.to_s.downcase] || arch.to_s.downcase
    end

    def can_build_locally?(target_arch)
      normalize(target_arch) == host_arch
    end

    def select_builder(target_arch)
      normalized = normalize(target_arch)

      if can_build_locally?(normalized)
        { type: :local, arch: normalized }
      else
        raise "Cannot build #{normalized} locally on #{host_arch} host"
      end
    end
  end
end
