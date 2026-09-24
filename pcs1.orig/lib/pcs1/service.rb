# frozen_string_literal: true

module Pcs1
  class Service
    # --- Shared helpers for all services ---

    def self.system_cmd(cmd, raise_on_error: true)
      Platform.system_cmd(cmd, raise_on_error: raise_on_error)
    end

    def self.capture(cmd)
      Platform.capture(cmd)
    end

    def self.command_exists?(cmd)
      Platform.command_exists?(cmd)
    end

    def self.sudo_write(path, content)
      Platform.sudo_write(path, content)
    end

    def self.render_template(relative_path, vars)
      template_path = Pcs1.resolve_template(relative_path)
      template = ERB.new(template_path.read, trim_mode: "-")
      template.result_with_hash(**vars)
    end

    def self.logger
      Pcs1.logger
    end
  end
end
