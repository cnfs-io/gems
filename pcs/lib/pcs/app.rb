# frozen_string_literal: true

require "termino/app"

# :nodoc:
module Pcs
  # The site's web UI: inventory pages and operations (routes/ adds them).
  class App < Termino::App
    route do |r|
      r.public
      r.hash_branches
      r.root { Views::Home.new }
    end
  end

  App.load_resources(__dir__)
  App.resource Termino::JobsResource
end
