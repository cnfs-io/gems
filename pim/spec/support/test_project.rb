# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module TestProject
  # Creates a scaffold project in a tmpdir, boots PIM against it.
  # Returns the project directory path.
  #
  # Usage:
  #   let(:project_dir) { TestProject.create }
  #   after { TestProject.cleanup(project_dir) }
  #
  def self.create(name: "test-project")
    tmp = Dir.mktmpdir("pim-spec-")
    target = File.join(tmp, name)
    Pim::New::Scaffold.new(target).create
    target
  end

  # Boot PIM against a project directory.
  # Call this after create, or after modifying data files.
  def self.boot(project_dir)
    Pim.boot!(project_dir: project_dir)
  end

  # Create and boot in one call.
  def self.create_and_boot(name: "test-project")
    dir = create(name: name)
    boot(dir)
    dir
  end

  # Cleanup a project tmpdir.
  def self.cleanup(project_dir)
    Pim.reset!
    # The tmpdir parent is one level up from the project dir
    parent = File.dirname(project_dir)
    FileUtils.remove_entry(parent) if parent.start_with?(Dir.tmpdir)
  end

  # Write additional records into a project's collection YAML file.
  # Merges with existing records (by appending).
  #
  #   TestProject.append_records(project_dir, "profiles", [
  #     { "id" => "dev", "parent_id" => "default", "packages" => "vim git" }
  #   ])
  #
  def self.append_records(project_dir, source_name, records)
    path = File.join(project_dir, "data", "#{source_name}.yml")

    existing = if File.exist?(path)
                 YAML.safe_load(File.read(path)) || []
               else
                 []
               end

    File.write(path, YAML.dump(existing + records))
  end

  # Overwrite a collection YAML file entirely.
  def self.write_records(project_dir, source_name, records)
    path = File.join(project_dir, "data", "#{source_name}.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(records))
  end
end
