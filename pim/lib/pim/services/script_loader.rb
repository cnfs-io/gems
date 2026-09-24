# frozen_string_literal: true

module Pim
  # Script loader for provisioning scripts
  class ScriptLoader
    SCRIPTS_DIR = 'resources/scripts'

    def initialize(project_dir: Dir.pwd)
      @project_dir = Pathname(project_dir)
    end

    # Find script by name: resources/scripts/<distro>/<name>.sh first, then resources/scripts/<name>.sh
    def find_script(name, distro: nil)
      (distro && find_file(File.join(SCRIPTS_DIR, distro), "#{name}.sh")) ||
        find_file(SCRIPTS_DIR, "#{name}.sh")
    end

    # Resolve list of script names to paths
    def resolve_scripts(script_names, distro: nil)
      script_names.map do |name|
        path = find_script(name, distro: distro)
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
