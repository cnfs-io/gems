# frozen_string_literal: true

require "open3"

module Pcs
  module Adapters
    # Runs local programs. Arguments are passed as argv, never through a
    # shell, so no value can be interpreted as shell syntax.
    class SystemCmd
      Result = Data.define(:argv, :stdout, :stderr, :status) do
        def success? = status.zero?

        def message
          "`#{argv.join(" ")}` failed (#{status}): #{stderr.strip.empty? ? stdout.strip : stderr.strip}"
        end
      end

      # A command run with run! didn't succeed; carries its Result.
      class Failed < Pcs::Error
        attr_reader :result

        def initialize(result)
          @result = result
          super(result.message)
        end
      end

      def run(*argv, input: nil, chdir: nil)
        argv = argv.flatten.map(&:to_s)
        options = { stdin_data: input.to_s }
        options[:chdir] = chdir.to_s if chdir
        stdout, stderr, status = Open3.capture3(*argv, **options)
        Result.new(argv, stdout, stderr, status.exitstatus)
      rescue Errno::ENOENT => e
        Result.new(argv, "", e.message, 127)
      end

      # Like run, but raises Failed unless the command succeeded.
      def run!(...)
        run(...).tap { |result| raise Failed, result unless result.success? }
      end
    end
  end
end
