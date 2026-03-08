# frozen_string_literal: true

module Pim
  class LocalTarget < Target
    sti_type "local"

    def deploy(image_path)
      puts "Image available at: #{image_path}"
      true
    end
  end
end
