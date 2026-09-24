# frozen_string_literal: true

module Pcs
  module Views
    # The page shell for every page. Override view_template (keep
    # `flash_messages` and `yield`) or stylesheets to change it.
    class Layout < Termino::Views::Layout
    end
  end
end
