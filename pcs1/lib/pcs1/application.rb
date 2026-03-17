# frozen_string_literal: true

module Pcs1
  class Application < RestCli::Application
    configure do |c|
      c.data_dir = "data"
    end
  end
end
