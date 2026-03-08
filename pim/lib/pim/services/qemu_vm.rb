# frozen_string_literal: true

require 'open3'
require 'socket'

module Pim
  # QEMU VM process management
  class QemuVM
    class Error < StandardError; end

    attr_reader :pid, :ssh_port

    def initialize(command:, ssh_port: nil)
      @command = command
      @ssh_port = ssh_port
      @pid = nil
      @process = nil
    end

    # Start the VM process
    def start
      @stdin, @stdout, @stderr, @process = Open3.popen3(*@command)
      @pid = @process.pid

      # Give QEMU a moment to start
      sleep 2

      # Check if process is still running
      unless running?
        output = @stderr.read rescue ''
        raise Error, "VM failed to start: #{output}"
      end

      self
    end

    # Start VM in background and return immediately
    def start_background(detach: true)
      @pid = spawn(*@command, [:out, :err] => '/dev/null')
      Process.detach(@pid) if detach
      @detached = detach

      sleep 2
      check_alive!
      self
    end

    # Start VM in background with serial/stdout captured to a log file.
    # Use with -nographic so serial goes to stdout, then stdout goes to the file.
    def start_background_with_log(log_path, detach: true)
      @log_file = File.open(log_path, 'w')
      @log_file.sync = true
      @pid = spawn(*@command, out: @log_file, err: @log_file)
      Process.detach(@pid) if detach
      @detached = detach

      sleep 2
      check_alive!(log_path: log_path)
      self
    end

    # Start VM with serial output going directly to the terminal
    def start_console(detach: true)
      @pid = spawn(*@command)
      Process.detach(@pid) if detach
      @detached = detach

      sleep 2
      self
    end

    # Wait for VM process to exit (only works when started with detach: false)
    def wait_for_exit(timeout: 3600, poll_interval: 10)
      deadline = Time.now + timeout

      while Time.now < deadline
        begin
          pid, status = Process.waitpid2(@pid, Process::WNOHANG)
          if pid
            @pid = nil
            return status.exitstatus || 0
          end
        rescue Errno::ECHILD
          @pid = nil
          return 0
        end

        remaining = (deadline - Time.now).to_i
        yield(remaining) if block_given?
        sleep(poll_interval)
      end

      nil
    end

    # Check if VM is running
    def running?
      return false unless @pid

      begin
        Process.kill(0, @pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true # Process exists but we can't signal it
      end
    end

    # Stop the VM gracefully (send ACPI shutdown)
    def shutdown(timeout: 60)
      return unless @pid && running?

      # Send SIGTERM first
      Process.kill('TERM', @pid)

      # Wait for graceful shutdown
      deadline = Time.now + timeout
      while Time.now < deadline && running?
        sleep 1
      end

      # Force kill if still running
      if running?
        Process.kill('KILL', @pid)
        sleep 1
      end
    end

    # Verify VM is still running after startup. Raises if it died immediately.
    def check_alive!(log_path: nil)
      return if running?

      hint = ""
      if log_path && File.exist?(log_path)
        output = File.read(log_path).strip
        hint = ": #{output}" unless output.empty?
      end

      raise Error, "VM exited immediately after start#{hint}"
    end

    # Force stop the VM
    def kill
      return unless @pid

      begin
        Process.kill('KILL', @pid)
      rescue Errno::ESRCH
        # Already dead
      end
    end

    # Wait for SSH port to be available (verifies SSH banner, not just TCP)
    def wait_for_ssh(timeout: 1800, poll_interval: 10, &block)
      return false unless @ssh_port

      deadline = Time.now + timeout
      attempt = 0

      while Time.now < deadline
        attempt += 1
        begin
          socket = TCPSocket.new('127.0.0.1', @ssh_port)
          ready = IO.select([socket], nil, nil, 10)
          if ready
            banner = socket.gets
            socket.close
            return true if banner&.start_with?('SSH-')
          else
            socket.close
          end
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ECONNRESET, IOError
          # Port not ready yet
        end

        remaining = (deadline - Time.now).to_i
        block.call(attempt, remaining) if block_given?
        sleep(poll_interval)
      end

      false
    end

    # Wait for process to exit
    def wait
      return nil unless @process

      @process.value.exitstatus
    end
  end
end
