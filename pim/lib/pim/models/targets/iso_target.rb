# frozen_string_literal: true

module Pim
  class IsoTarget < Target
    sti_type "iso"

    attribute :output_dir, :string

    def deploy(image_path)
      puts "Repacked ISO available at: #{image_path}"
      true
    end
  end
end
