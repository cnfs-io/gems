# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module Pim
  module New
    class Scaffold
      SCAFFOLD_DIRS = %w[
        data
        resources/post_installs resources/preseeds resources/scripts resources/verifications
      ].freeze

      TEMPLATE_DIR = File.expand_path("template", __dir__)

      def initialize(target_dir)
        @target_dir = File.expand_path(target_dir)
      end

      def create
        if File.exist?(File.join(@target_dir, Pim::PROJECT_MARKER))
          raise "Project already exists at #{@target_dir}"
        end

        FileUtils.mkdir_p(@target_dir)

        SCAFFOLD_DIRS.each do |dir|
          FileUtils.mkdir_p(File.join(@target_dir, dir))
        end

        copy_templates

        puts "Created PIM project at #{@target_dir}"
        puts "  #{Pim::PROJECT_MARKER}"
        SCAFFOLD_DIRS.each { |d| puts "  #{d}/" }
      end

      private

      def copy_templates
        Dir.glob(File.join(TEMPLATE_DIR, "**", "*"), File::FNM_DOTMATCH).each do |src|
          next if File.directory?(src)

          rel = Pathname.new(src).relative_path_from(Pathname.new(TEMPLATE_DIR)).to_s
          dest = File.join(@target_dir, rel)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
        end
      end
    end
  end
end
