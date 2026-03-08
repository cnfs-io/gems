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
        v = config.ventoy
        puts "ventoy.version=#{v.version}" if v.version
        puts "ventoy.device=#{v.device}" if v.device
        puts "ventoy.dir=#{v.dir}" if v.dir
        puts "ventoy.file=#{v.file}" if v.file
        puts "ventoy.url=#{v.url}" if v.url
        puts "ventoy.checksum=#{v.checksum}" if v.checksum
      end
    end

    class Get < self
      desc "Get a configuration value by name"

      argument :key, required: true, desc: "Configuration key (e.g., memory, serve_port, ventoy.version)"

      def call(key:, **)
        config = Pim.config
        parts = key.split('.')

        value = if parts.size == 2 && parts.first == 'ventoy'
                  config.ventoy.public_send(parts.last) rescue nil
                elsif parts.size == 1 && config.respond_to?(key)
                  config.public_send(key)
                end

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
