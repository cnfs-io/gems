# frozen_string_literal: true

require "dry/cli"
require "erb"
require "fileutils"
require "pathname"
require "tty-prompt"

module Pcs
  module Commands
    class New < Dry::CLI::Command
      desc "Scaffold a new PCS project"

      argument :name, required: true, desc: "Project name (e.g., rws-pcs)"
      option :force, type: :boolean, default: false, aliases: ["-f"], desc: "Remove existing directory before creating"

      TEMPLATE_DIR = Pathname.new(__dir__).join("..", "templates", "project")

      def call(name:, force: false, **)
        root = Pathname.pwd / name

        if root.exist?
          if force
            root.rmtree
          else
            $stderr.puts "Error: Directory '#{name}' already exists."
            exit 1
          end
        end

        prompt = TTY::Prompt.new
        domain = prompt.ask("Domain:", default: "#{name}.internal")

        # Create directories
        (root / "sites").mkpath
        (root / "data").mkpath

        # Render templates
        write_template(root / "pcs.rb", "pcs.rb.erb", name: name, domain: domain)
        write_template(root / ".gitignore", "gitignore.erb", name: name)
        write_template(root / "README.md", "README.md.erb", name: name)

        # Copy static data files
        FileUtils.cp(TEMPLATE_DIR / "roles.yml", root / "data" / "roles.yml")
      end

      private

      def write_template(dest, template_name, **locals)
        template = (TEMPLATE_DIR / template_name).read
        content = ERB.new(template, trim_mode: "-").result_with_hash(**locals)
        dest.write(content)
      end
    end
  end
end
