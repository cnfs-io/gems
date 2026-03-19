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
      config_path = Pcs1.root / Pcs1::PROJECT_MARKER
      load(config_path.to_s) if config_path.exist?
    end
  end
end
