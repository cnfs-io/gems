# frozen_string_literal: true

require "erb"
require "pathname"
require "logger"

require "flat_record"
require "net/ssh"
require "rest_cli"
require "state_machines"
require "state_machines-activemodel"

lib_dir = Pathname.new(__dir__).join("pcs1")

# Auto-require all Ruby files under commands/
dir = lib_dir.join('commands').glob("**/*.rb").each { |file| require file }

# Auto-require all Ruby files in lib dir
lib_dir.glob("*.rb").each { |file| require file }

# Auto-require all Ruby files under lib/pcs1/{models,views,etc.} except commands
lib_dir.children.select(&:directory?).reject{ |p| p.split.last.to_s.eql?('commands') }.each do |dir|
  dir.glob("**/*.rb").each { |file| require file }
end

module Pcs1
  class Error < StandardError; end

  GEM_TEMPLATE_DIR = Pathname.new(__dir__).join("pcs1", "templates")
  PROJECT_MARKER = "pcs.rb"

  def self.root
    @root ||= find_root
  end

  def self.logger
    @logger ||= build_logger
  end

  def self.logger=(new_logger)
    @logger = new_logger
  end

  def self.configure
    @config ||= Config.new
    yield @config if block_given?
    @logger = nil
    @config
  end

  def self.config
    @config || configure
  end

  def self.site
    @site ||= resolve_site
  end

  def self.reset!
    @site = nil
    @config = nil
    @logger = nil
    @root = nil
  end

  def self.resolve_template(relative_path)
    project_path = root / "templates" / relative_path
    return project_path if project_path.exist?

    gem_path = GEM_TEMPLATE_DIR / relative_path
    return gem_path if gem_path.exist?

    raise Error, "Template not found: #{relative_path}"
  end

  def self.gem_templates
    GEM_TEMPLATE_DIR.glob("**/*.erb").map do |path|
      path.relative_path_from(GEM_TEMPLATE_DIR).to_s
    end.sort
  end

  def self.resolve_site
    host = Host.local
    host&.site
  end

  def self.find_root
    dir = Pathname.pwd
    loop do
      return dir if (dir / PROJECT_MARKER).exist?

      parent = dir.parent
      return Pathname.pwd if parent == dir

      dir = parent
    end
  end

  def self.build_logger
    output = config.log_output
    level = config.log_level

    Logger.new(output).tap do |log|
      log.progname = "pcs1"
      log.level = case level
                  when :debug then Logger::DEBUG
                  when :info  then Logger::INFO
                  when :warn  then Logger::WARN
                  when :error then Logger::ERROR
                  else Logger::INFO
                  end
      log.formatter = proc do |severity, _time, _progname, msg|
        "  [#{severity.downcase}] #{msg}\n"
      end
    end
  end
end
