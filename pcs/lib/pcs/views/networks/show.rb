# frozen_string_literal: true

module Pcs
  module Views
    module Networks
      # A network, with the interfaces on it.
      class Show < Termino::Views::Show
        private

        def related
          render InterfaceTable.new(interfaces: @record.interfaces.to_a, show: :host)
        end
      end
    end
  end
end
