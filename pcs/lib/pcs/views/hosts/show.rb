# frozen_string_literal: true

module Pcs
  module Views
    module Hosts
      # A host, with its interfaces and what it still needs to be configured.
      class Show < Termino::Views::Show
        private

        # Keying a device that ships with a password takes that password once.
        def event_button(event)
          return super unless event == "key" && @record.key_install_command("")

          form(action: "#{resource.record_path(@record)}/events/key", method: "post", class: "flex gap-2") do
            Input(type: "password", name: "password", autocomplete: "off", class: "w-72",
                  placeholder: "#{@record.ssh_user}'s password (if pcs's key isn't on it yet)")
            Button(type: :submit, variant: :secondary) { hooks.event_label(event) }
          end
        end

        def related
          missing = @record.missing_configuration
          if missing.any? && !@record.provisioned?
            p(class: "mt-8 text-sm text-muted-foreground") do
              "To configure: set #{missing.map { |m| m.to_s.humanize(capitalize: false) }.join(", ")}."
            end
          end
          render InterfaceTable.new(interfaces: @record.interfaces.to_a)
        end
      end
    end
  end
end
