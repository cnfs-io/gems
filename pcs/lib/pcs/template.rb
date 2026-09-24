# frozen_string_literal: true

require "erb"

module Pcs
  # Renders the files pcs generates (dnsmasq config, boot menus, preseeds)
  # from ERB templates. A project overrides one by putting its own copy in
  # templates/ (e.g. templates/preseed.cfg.erb); the gem's are the default.
  module Template
    DIR = File.join(__dir__, "templates")

    module_function

    def render(name, **locals)
      ERB.new(File.read(path(name)), trim_mode: "-").result_with_hash(locals)
    end

    # The project's copy if it has one, else the gem's.
    def path(name)
      file = "#{name}.erb"
      root = Termino::Project.root
      custom = root && File.join(root, "templates", file)
      return custom if custom && File.exist?(custom)

      File.join(DIR, file).tap { |default| raise Pcs::Error, "no template #{file}" unless File.exist?(default) }
    end

    def names
      Dir[File.join(DIR, "*.erb")].map { |f| File.basename(f, ".erb") }.sort
    end
  end
end
