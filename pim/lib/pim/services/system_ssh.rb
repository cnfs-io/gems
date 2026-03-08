# frozen_string_literal: true

require 'open3'
require 'shellwords'

module Pim
  # Execute SSH command via system ssh (fallback when net-ssh is unavailable)
  class SystemSSH
    def initialize(host:, port: 22, user:, key_file: nil)
      @host = host
      @port = port
      @user = user
      @key_file = key_file
    end

    def execute(command, sudo: false)
      ssh_cmd = build_ssh_command
      full_command = sudo ? "sudo #{command}" : command

      stdout, stderr, status = Open3.capture3("#{ssh_cmd} #{shell_escape(full_command)}")

      { stdout: stdout, stderr: stderr, exit_code: status.exitstatus }
    end

    def upload(local_path, remote_path)
      scp_cmd = build_scp_command
      system("#{scp_cmd} #{shell_escape(local_path)} #{@user}@#{@host}:#{shell_escape(remote_path)}")
    end

    private

    def build_ssh_command
      cmd = ['ssh', '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null']
      cmd += ['-p', @port.to_s] if @port != 22
      cmd += ['-i', @key_file] if @key_file
      cmd << "#{@user}@#{@host}"
      cmd.join(' ')
    end

    def build_scp_command
      cmd = ['scp', '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null']
      cmd += ['-P', @port.to_s] if @port != 22
      cmd += ['-i', @key_file] if @key_file
      cmd.join(' ')
    end

    def shell_escape(str)
      Shellwords.escape(str)
    end
  end
end
