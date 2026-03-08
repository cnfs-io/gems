# frozen_string_literal: true

require "pathname"

module Pcs
  PROJECT_MARKER = "pcs.rb"

  class ProjectNotFoundError < StandardError; end
  class SiteNotSetError < StandardError; end

  def self.root(start_dir = Dir.pwd)
    dir = Pathname(start_dir).expand_path
    loop do
      return dir if (dir / PROJECT_MARKER).exist?
      parent = dir.parent
      return nil if parent == dir
      dir = parent
    end
  end

  def self.root!(start_dir = Dir.pwd)
    root(start_dir) || raise(ProjectNotFoundError, "No pcs.rb found. Run `pcs new` to create a project.")
  end

  def self.project_dir
    @project_dir ||= root!
  end

  def self.data_dir
    project_dir / "data"
  end

  def self.sites_dir
    project_dir / "sites"
  end

  def self.site_dir(site_name = site)
    sites_dir / site_name
  end

  def self.states_dir
    project_dir / "states"
  end

  def self.state_dir(site_name = site)
    states_dir / site_name
  end

  def self.site
    @site ||= resolve_site
  end

  def self.site=(name)
    @site = name
  end

  def self.boot!(project_dir: nil)
    @project_dir = project_dir ? Pathname(project_dir) : root!
    @config = nil
    @site = nil

    # Load pcs.rb — executes Pcs.configure and any model-level overrides
    load(@project_dir.join(PROJECT_MARKER).to_s)

    # Apply FlatRecord configuration from the nested config block
    apply_flat_record_config!

    # Set data paths for non-hierarchical models
    Pcs::Role.data_paths = [data_dir] if defined?(Pcs::Role)

    # Reload models
    reload_models!
  end

  def self.load_provider_config(name)
    path = project_dir / "config" / "#{name}.yml"
    return {} unless path.exist?
    YAML.safe_load_file(path, symbolize_names: true) || {}
  end

  def self.reset!
    @project_dir = nil
    @config = nil
    @site = nil
  end

  private

  def self.resolve_site
    require "dotenv"
    Dotenv.load(project_dir / ".env")
    ENV.fetch("PCS_SITE") do
      raise SiteNotSetError, "No site selected. Run 'pcs site use <site>' or set PCS_SITE in .env"
    end
  end

  def self.apply_flat_record_config!
    fr_settings = config.flat_record

    FlatRecord.configure do |c|
      c.backend = fr_settings.backend
      c.data_path = sites_dir
      c.id_strategy = fr_settings.id_strategy
      c.on_missing_file = fr_settings.on_missing_file
      c.merge_strategy = fr_settings.merge_strategy
      c.read_only = fr_settings.read_only

      if fr_settings.hierarchy_model
        c.enable_hierarchy(
          model: fr_settings.hierarchy_model,
          key: fr_settings.hierarchy_key
        )
      end
    end
  end

  def self.reload_models!
    Pcs::Role.reload! if defined?(Pcs::Role)
    Pcs::Site.reload! if defined?(Pcs::Site)
    Pcs::Network.reload! if defined?(Pcs::Network)
    Pcs::Host.reload! if defined?(Pcs::Host)
    Pcs::Interface.reload! if defined?(Pcs::Interface)
    Pcs::Profile.reload! if defined?(Pcs::Profile)
  end
end
