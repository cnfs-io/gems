# frozen_string_literal: true

require "open3"
require "json"
require "pathname"

module Pcs
  module Adapters
    class SystemCmd
      FailedStatus = Data.define(:exitstatus) do
        def success? = false
      end

      Result = Data.define(:stdout, :stderr, :status) do
        def success? = status.success?
      end

      def run(cmd, sudo: false)
        full_cmd = sudo ? "sudo #{cmd}" : cmd
        stdout, stderr, status = Open3.capture3(full_cmd)
        Result.new(stdout: stdout, stderr: stderr, status: status)
      rescue Errno::ENOENT => e
        binary = cmd.split.first
        Result.new(
          stdout: "",
          stderr: "Command not found: #{binary} (#{e.message})",
          status: FailedStatus.new(exitstatus: 127)
        )
      end

      def run!(cmd, sudo: false)
        result = run(cmd, sudo: sudo)
        unless result.success?
          raise "Command failed: #{cmd}\nstderr: #{result.stderr}"
        end

        result
      end

      def ip_json(subcommand)
        result = run!("ip -j #{subcommand}")
        JSON.parse(result.stdout)
      end

      def file_write(path, content, sudo: false)
        if sudo
          IO.popen(["sudo", "tee", path.to_s], "w", out: File::NULL) { |io| io.write(content) }
        else
          Pathname.new(path).write(content)
        end
      end

      def service(action, name)
        run!("systemctl #{action} #{name}", sudo: true)
      end

      def apt_install(*packages)
        run!("apt-get install -y #{packages.join(" ")}", sudo: true)
      end

      SBIN_DIRS = %w[/usr/sbin /sbin /usr/local/sbin].freeze

      def command_exists?(cmd)
        search_dirs = ENV.fetch("PATH", "").split(":") | SBIN_DIRS
        search_dirs.any? do |dir|
          File.executable?(File.join(dir, cmd))
        end
      end
    end
  end
end
