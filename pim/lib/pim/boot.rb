# frozen_string_literal: true

module Pim
  PROJECT_MARKER = "pim.rb"

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
    root(start_dir) || raise("No pim.rb found. Run `pim new` to create a project.")
  end

  def self.project_dir
    @project_dir ||= root!
  end

  def self.data_dir(project_dir = nil)
    (project_dir ? Pathname(project_dir) : self.project_dir) / "data"
  end

  def self.resources_dir(project_dir = nil)
    (project_dir ? Pathname(project_dir) : self.project_dir) / "resources"
  end

  def self.data_home
    File.join(XDG_DATA_HOME, 'pim')
  end

  def self.boot!(project_dir: nil)
    @project_dir = project_dir ? Pathname(project_dir) : root!
    @config = nil

    # Load pim.rb — this executes Pim.configure and any model-level overrides
    load(@project_dir.join(PROJECT_MARKER).to_s)

    # Apply FlatRecord configuration from the nested config block
    apply_flat_record_config!

    # Reload all models
    reload_models!
  end

  def self.reset!
    @project_dir = nil
    @config = nil
  end

  private_class_method def self.apply_flat_record_config!
    fr_settings = config.flat_record

    FlatRecord.configure do |c|
      c.backend = fr_settings.backend
      c.data_path = data_dir
      c.id_strategy = fr_settings.id_strategy
      c.on_missing_file = fr_settings.on_missing_file
      c.merge_strategy = fr_settings.merge_strategy
      c.read_only = fr_settings.read_only
    end
  end

  private_class_method def self.reload_models!
    Pim::Iso.reload!
    Pim::Build.reload!
    Pim::Target.reload!
    Pim::Profile.reload!
  end
end
