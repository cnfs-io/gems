# frozen_string_literal: true

module Pcs1
  module Platform
    def self.current
      @current ||= case RUBY_PLATFORM
                   when /darwin/ then Darwin.new
                   when /linux/  then Linux.new
                   else raise "Unsupported platform: #{RUBY_PLATFORM}"
                   end
    end

    def self.reset!
      @current = nil
    end

    # Execute a system command with logging.
    # Returns true on success, raises on failure if raise_on_error is true.
    def self.system_cmd(cmd, raise_on_error: true)
      Pcs1.logger.debug("exec: #{cmd}")
      success = system(cmd)
      if success
        Pcs1.logger.debug("exec: ok")
      else
        msg = "Command failed: #{cmd}"
        Pcs1.logger.error(msg)
        raise msg if raise_on_error
      end
      success
    end

    # Execute a command and return its stdout (for queries, not mutations).
    def self.capture(cmd)
      Pcs1.logger.debug("capture: #{cmd}")
      `#{cmd} 2>/dev/null`.strip
    end

    # Check if a command exists on the system.
    def self.command_exists?(cmd)
      system("command -v #{cmd} > /dev/null 2>&1")
    end

    # Write a file via sudo tee (for root-owned paths).
    def self.sudo_write(path, content)
      path = Pathname(path)
      system_cmd("sudo mkdir -p #{path.dirname}", raise_on_error: false)
      IO.popen(["sudo", "tee", path.to_s], "w", out: File::NULL) { |io| io.write(content) }
      Pcs1.logger.debug("wrote: #{path}")
    end
  end
end

require_relative "platform/linux"
require_relative "platform/darwin"
