# frozen_string_literal: true

module Pim
  class ConfigCommand < RestCli::Command
    class List < self
      desc "List all configuration values"

      def call(**)
        config = Pim.config
        puts "iso_dir=#{config.iso_dir}"
        puts "image_dir=#{config.image_dir}"
        puts "serve_port=#{config.serve_port}"
        puts "serve_profile=#{config.serve_profile}" if config.serve_profile
      end
    end

    class Get < self
      desc "Get a configuration value by name"

      argument :key, required: true, desc: "Configuration key (e.g., iso_dir, serve_port)"

      def call(key:, **)
        config = Pim.config
        value = config.public_send(key) if config.respond_to?(key)

        if value.nil?
          Pim.exit!(1, message: "Error: key '#{key}' not found")
        end

        puts value
      end
    end

    class Set < self
      desc "Set a configuration value (updates pim.rb is not supported — edit pim.rb directly)"

      argument :key, required: true, desc: "Configuration key"
      argument :value, required: true, desc: "Value to set"

      def call(key:, value:, **)
        puts "Config is now managed via pim.rb. Edit your project's pim.rb to change settings."
        puts "Example: Pim.configure { |c| c.#{key} = #{coerce(value).inspect} }"
      end

      private

      def coerce(value)
        case value
        when /\A-?\d+\z/ then value.to_i
        when /\A-?\d+\.\d+\z/ then value.to_f
        when 'true' then true
        when 'false' then false
        else value
        end
      end
    end
  end
end
