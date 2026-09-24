# frozen_string_literal: true

require "pathname"
require "fileutils"

module Pcs1
  class TemplatesCommand < RestCli::Command
    class List < self
      desc "List available templates"

      def call(**)
        templates = Pcs1.gem_templates

        if templates.empty?
          puts "No templates found."
          return
        end

        puts "Available templates:"
        puts

        templates.each do |t|
          project_path = Pathname.pwd / "templates" / t
          customized = project_path.exist? ? " (customized)" : ""
          puts "  #{t}#{customized}"
        end

        puts
        puts "Customize a template: pcs1 template customize <path>"
      end
    end

    class Customize < self
      desc "Copy a gem template into the project for editing"

      argument :path, required: true, desc: "Template path (e.g., proxmox/install.sh.erb)"

      def call(path:, **)
        gem_path = Pcs1::GEM_TEMPLATE_DIR / path

        unless gem_path.exist?
          warn "Error: Template '#{path}' not found in gem."
          warn "Run 'pcs1 template list' to see available templates."
          exit 1
        end

        project_path = Pathname.pwd / "templates" / path

        if project_path.exist?
          warn "Template already customized at #{project_path}"
          exit 1
        end

        project_path.dirname.mkpath
        FileUtils.cp(gem_path, project_path)
        puts "Copied #{path} to #{project_path}"
        puts "Edit this file to customize. PCS will use it instead of the gem default."
      end
    end

    class Reset < self
      desc "Remove a customized template (revert to gem default)"

      argument :path, required: true, desc: "Template path"

      def call(path:, **)
        project_path = Pathname.pwd / "templates" / path

        unless project_path.exist?
          warn "No customized template at #{project_path}"
          exit 1
        end

        prompt = TTY::Prompt.new
        unless prompt.yes?("Remove #{project_path} and revert to gem default?", default: false)
          puts "Aborted."
          return
        end

        project_path.delete
        puts "Removed #{project_path} — using gem default."
      end
    end
  end
end
