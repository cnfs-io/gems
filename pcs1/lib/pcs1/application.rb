# frozen_string_literal: true

module Pcs1
  class Application < RestCli::Application
    configure do |c|
      c.data_dir = "data"
    end

    def self.boot!
      super
      load_project_config
    end

    def self.load_project_config
      config_path = File.join(Dir.pwd, "pcs.rb")
      load(config_path) if File.exist?(config_path)
    end
  end
end
