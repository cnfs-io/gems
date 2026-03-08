# frozen_string_literal: true

require "yaml"
require "erb"
require "webrick"
require "socket"
require "pathname"
require "fileutils"
module Pim
  # XDG base directories — defined early so sub-files can reference them
  XDG_CONFIG_HOME = ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')) unless const_defined?(:XDG_CONFIG_HOME)
  XDG_DATA_HOME = ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')) unless const_defined?(:XDG_DATA_HOME)
  XDG_CACHE_HOME = ENV.fetch('XDG_CACHE_HOME', File.expand_path('~/.cache')) unless const_defined?(:XDG_CACHE_HOME)
end

require_relative "pim/version"

# Boot and config
require_relative "pim/boot"
require_relative "pim/config"
require_relative "pim/image"

# Scaffold
require_relative "pim/new/scaffold"

# Services
require_relative "pim/services/http"
require_relative "pim/services/qemu"
require_relative "pim/services/qemu_disk_image"
require_relative "pim/services/qemu_command_builder"
require_relative "pim/services/qemu_vm"
require_relative "pim/services/ssh_connection"
require_relative "pim/services/system_ssh"
require_relative "pim/services/architecture_resolver"
require_relative "pim/services/cache_manager"
require_relative "pim/services/script_loader"
require_relative "pim/services/ventoy_config"
require_relative "pim/services/ventoy_manager"
require_relative "pim/services/registry"
require_relative "pim/services/verifier"
require_relative "pim/services/vm_runner"
require_relative "pim/services/vm_registry"

# Models
require_relative "pim/models"

# Build pipeline
require_relative "pim/build/local_builder"
require_relative "pim/build/manager"

# Views
require_relative "pim/views"

# CLI
require_relative "pim/cli"

module Pim

  # Console-safe error for command failures
  class CommandError < StandardError; end

  # Commands that don't require a project
  BOOT_SKIP_COMMANDS = %w[new version completions].freeze unless const_defined?(:BOOT_SKIP_COMMANDS)

  @console_mode = false

  def self.console_mode!
    @console_mode = true
  end

  def self.console_mode?
    @console_mode == true
  end

  def self.exit!(code = 1, message: nil)
    $stderr.puts(message) if message
    if console_mode?
      raise CommandError, message || "command failed (exit #{code})"
    else
      Kernel.exit(code)
    end
  end

  def self.run(*args)
    flat_args = args.flat_map { |a| a.split(" ") }

    unless BOOT_SKIP_COMMANDS.include?(flat_args.first)
      boot!
    end

    Dry::CLI.new(Pim::CLI).call(arguments: flat_args)
  rescue CommandError => e
    $stderr.puts e.message
  rescue RuntimeError => e
    $stderr.puts e.message
  rescue SystemExit
    # swallow exits in console mode
  end

  # WEBrick server for serving preseed and post-install scripts
  class Server
    def initialize(profile:, port: 8080, verbose: false, debug: false, preseed_name: nil, install_name: nil)
      @profile = profile
      @port = port
      @verbose = verbose
      @debug = debug
      @preseed_name = preseed_name
      @install_name = install_name
      @ip = local_ip
    end

    def start
      preseed_path = '/preseed.cfg'
      install_path = '/install.sh'

      install_content = read_file(@profile.install_template(@install_name))

      bindings = @profile.to_h.transform_keys(&:to_sym)
      bindings[:install_url] = "http://#{@ip}:#{@port}#{install_path}" if install_content

      preseed_content = render_template(@profile.preseed_template(@preseed_name), bindings)

      puts "Serving preseed configuration for profile: #{@profile.name}"
      puts
      puts "Preseed URL:      http://#{@ip}:#{@port}#{preseed_path}"
      puts "Install URL:      http://#{@ip}:#{@port}#{install_path}" if install_content
      puts

      if @debug
        puts '=' * 60
        puts "preseed.cfg:"
        puts '=' * 60
        puts preseed_content
        puts
        if install_content
          puts '=' * 60
          puts "install.sh:"
          puts '=' * 60
          puts install_content
          puts
        end
      end

      puts "Boot parameters:"
      puts "  auto=true priority=critical preseed/url=http://#{@ip}:#{@port}#{preseed_path}"
      puts
      puts "Press Ctrl+C to stop"
      puts

      log_level = @verbose ? WEBrick::Log::DEBUG : WEBrick::Log::WARN
      server = WEBrick::HTTPServer.new(
        Port: @port,
        Logger: WEBrick::Log.new($stdout, log_level),
        AccessLog: @verbose ? [[File.open('/dev/stdout', 'w'), WEBrick::AccessLog::COMMON_LOG_FORMAT]] : []
      )

      server.mount_proc(preseed_path) do |_req, res|
        res['Content-Type'] = 'text/plain'
        res.body = preseed_content
      end

      if install_content
        server.mount_proc(install_path) do |_req, res|
          res['Content-Type'] = 'text/plain'
          res.body = install_content
        end
      end

      trap('INT') { server.shutdown }
      trap('TERM') { server.shutdown }

      server.start
    end

    private

    def render_template(template_path, bindings = nil)
      return nil unless template_path && File.exist?(template_path)

      bindings ||= @profile.to_h.transform_keys(&:to_sym)
      template_content = File.read(template_path)

      template_content.scan(/<%=?\s*(\w+)/).flatten.uniq.each do |var|
        bindings[var.to_sym] = nil unless bindings.key?(var.to_sym)
      end

      template = ERB.new(template_content)
      template.result_with_hash(bindings)
    end

    def read_file(path)
      return nil unless path && File.exist?(path)
      File.read(path)
    end

    def local_ip
      Socket.ip_address_list
            .detect { |addr| addr.ipv4? && !addr.ipv4_loopback? }
            &.ip_address || '127.0.0.1'
    end
  end
end
