# frozen_string_literal: true

require "fileutils"
require "net/ssh"
require "shellwords"

module Pcs
  module Adapters
    # Runs commands on a host over SSH, as argv (quoted for the remote shell,
    # never interpolated). Uses one explicit key, and trusts a host's key the
    # first time it's seen, pinning it in the project's known_hosts.
    #
    # With a password (only to install pcs's key on a device that ships with
    # one, like a PiKVM), it logs in with that instead; the password is never
    # stored.
    class Ssh
      Result = SystemCmd::Result

      def initialize(host:, user:, key_path:, known_hosts:, port: 22, timeout: 10, password: nil)
        @host = host
        @user = user
        @key_path = key_path
        @known_hosts = known_hosts
        @port = port
        @timeout = timeout
        @password = password
      end

      # Drops the pinned host key for this host (it was reinstalled, so its
      # key changed); the next connection trusts the new one.
      def forget_host_key
        return unless File.exist?(@known_hosts)

        names = [@host, "[#{@host}]:#{@port}"]
        kept = File.readlines(@known_hosts).reject { |line| (line.split.first.to_s.split(",") & names).any? }
        File.write(@known_hosts, kept.join)
      end

      def run(*argv, input: nil)
        argv = argv.flatten.map(&:to_s)
        out, err, code = session { |ssh| exec(ssh, self.class.command(argv), input) }
        Result.new(argv, out, err, code)
      end

      def run!(...)
        run(...).tap { |result| raise SystemCmd::Failed, result unless result.success? }
      end

      # Writes content to path on the host (content goes over stdin, not argv).
      def upload(content, path, mode: "0644")
        run!("sh", "-c", 'umask 077 && cat > "$1" && chmod "$2" "$1"', "upload", path, mode, input: content)
      end

      # Whether pcs can log in with its key.
      def reachable?
        session { true }
      rescue Net::SSH::Exception, SystemCallError, Timeout::Error, SocketError
        false
      end

      # The remote command line for argv.
      def self.command(argv)
        Shellwords.join(argv)
      end

      private

      def session(&)
        FileUtils.mkdir_p(File.dirname(@known_hosts))
        Net::SSH.start(@host, @user, port: @port, timeout: @timeout, non_interactive: true,
                                     verify_host_key: :accept_new, user_known_hosts_file: @known_hosts,
                                     global_known_hosts_file: [], **credentials, &)
      end

      def credentials
        return { keys: [@key_path], keys_only: true, auth_methods: ["publickey"] } unless @password

        { password: @password, auth_methods: %w[password keyboard-interactive], keys: [], keys_only: true }
      end

      # Runs command, feeding it input; returns [stdout, stderr, exit status].
      def exec(ssh, command, input)
        output = { out: +"", err: +"", code: 255 }
        ssh.open_channel do |channel|
          channel.exec(command) do |ch, ok|
            raise Pcs::Error, "couldn't run #{command} on #{@host}" unless ok

            collect(ch, output)
            ch.send_data(input.to_s) if input
            ch.eof!
          end
        end.wait
        output.values_at(:out, :err, :code)
      end

      def collect(channel, output)
        channel.on_data { |_, data| output[:out] << data }
        channel.on_extended_data { |_, _, data| output[:err] << data }
        channel.on_request("exit-status") { |_, data| output[:code] = data.read_long }
      end
    end
  end
end
