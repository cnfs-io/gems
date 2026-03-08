# frozen_string_literal: true

module Pim
  # Script loader for provisioning scripts
  class ScriptLoader
    SCRIPTS_DIR = 'resources/scripts'

    def initialize(project_dir: Dir.pwd)
      @project_dir = Pathname(project_dir)
    end

    # Find script by name (follows naming convention with fallback)
    def find_script(name)
      find_file(SCRIPTS_DIR, "#{name}.sh")
    end

    # Resolve list of script names to paths
    def resolve_scripts(script_names)
      script_names.map do |name|
        path = find_script(name)
        raise "Script not found: #{name}.sh" unless path

        path
      end
    end

    # Get script content
    def script_content(name)
      path = find_script(name)
      return nil unless path

      File.read(path)
    end

    private

    def find_file(subdir, filename)
      project_path = @project_dir.join(subdir, filename)
      return project_path.to_s if project_path.exist?
      nil
    end
  end
end
