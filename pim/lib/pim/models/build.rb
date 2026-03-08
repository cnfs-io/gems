# frozen_string_literal: true

module Pim
  class Build < FlatRecord::Base
    source "builds"
    merge_strategy :deep_merge

    attribute :profile, :string
    attribute :iso, :string
    attribute :distro, :string
    attribute :automation, :string
    attribute :build_method, :string
    attribute :arch, :string
    attribute :target, :string
    attribute :disk_size, :string
    attribute :memory, :integer
    attribute :cpus, :integer
    attribute :ssh_user, :string
    attribute :ssh_timeout, :integer

    def disk_size
      super || "20G"
    end

    def memory
      super || 2048
    end

    def cpus
      super || 2
    end

    def ssh_user
      super || "ansible"
    end

    def ssh_timeout
      super || 1800
    end

    def resolved_profile
      Pim::Profile.find(profile)
    end

    def resolved_iso
      Pim::Iso.find(iso)
    end

    def resolved_target
      return nil unless target
      Pim::Target.find(target)
    end

    def arch
      super || Pim::ArchitectureResolver.new.host_arch
    end

    def build_method
      super || "qemu"
    end

    def automation
      super || infer_automation
    end

    def to_h
      attributes.compact
    end

    private

    def infer_automation
      case distro
      when "debian", "ubuntu" then "preseed"
      when "rhel", "fedora", "alma", "rocky" then "kickstart"
      else "preseed"
      end
    end
  end
end
