# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Pim
  class VmRegistry
    STATE_DIR_NAME = 'vms'

    def initialize
      @state_dir = File.join(runtime_dir, STATE_DIR_NAME)
      FileUtils.mkdir_p(@state_dir)
    end

    # Register a running VM, returns the assigned instance name
    def register(name:, pid:, build_id:, image_path:, ssh_port: nil,
                 network: 'user', mac: nil, snapshot: true)
      actual_name = unique_name(name)

      state = {
        'name' => actual_name,
        'pid' => pid,
        'build_id' => build_id,
        'image_path' => image_path,
        'ssh_port' => ssh_port,
        'network' => network,
        'mac' => mac,
        'bridge_ip' => nil,
        'snapshot' => snapshot,
        'started_at' => Time.now.utc.iso8601
      }

      File.write(state_file(actual_name), YAML.dump(state))
      actual_name
    end

    # Update a field (e.g., bridge_ip after discovery)
    def update(name, **fields)
      path = state_file(name)
      return unless File.exist?(path)

      state = YAML.safe_load_file(path, permitted_classes: [Time])
      fields.each { |k, v| state[k.to_s] = v }
      File.write(path, YAML.dump(state))
    end

    # List all registered VMs, pruning dead ones
    def list
      entries = []
      Dir.glob(File.join(@state_dir, '*.yml')).each do |path|
        state = YAML.safe_load_file(path, permitted_classes: [Time])
        next unless state.is_a?(Hash)

        pid = state['pid']
        if pid && process_alive?(pid)
          entries << state
        else
          File.delete(path)
        end
      end

      entries.sort_by { |e| e['started_at'] || '' }
    end

    # Find a VM by name or numeric index (1-based)
    def find(identifier)
      all = list
      return nil if all.empty?

      # Try numeric index first (1-based)
      if identifier.match?(/\A\d+\z/)
        idx = identifier.to_i - 1
        return all[idx] if idx >= 0 && idx < all.size
      end

      # Try name match
      all.find { |e| e['name'] == identifier }
    end

    # Unregister a VM (remove state file)
    def unregister(name)
      path = state_file(name)
      File.delete(path) if File.exist?(path)
    end

    private

    def runtime_dir
      Pim::Qemu.runtime_dir
    end

    def state_file(name)
      File.join(@state_dir, "#{name}.yml")
    end

    def unique_name(base)
      return base unless File.exist?(state_file(base))

      counter = 2
      loop do
        candidate = "#{base}-#{counter}"
        return candidate unless File.exist?(state_file(candidate))
        counter += 1
      end
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true # exists but different user (sudo/root)
    end
  end
end
