# frozen_string_literal: true

require "tty-prompt"

module Pcs1
  class SitesCommand < RestCli::Command
    class Add < self
      desc "Create the site for this project"

      def call(**options)
        if Pcs1::Site.all.any?
          warn "Error: Site already exists. Use 'pcs1 site update' to modify."
          exit 1
        end

        prompt = TTY::Prompt.new

        name     = prompt_field(prompt, Pcs1::Site.new, :name)
        domain   = prompt_field(prompt, Pcs1::Site.new(name: name), :domain,
                                default: "#{name}.local")
        timezone = prompt_field(prompt, Pcs1::Site.new, :timezone)
        ssh_key  = prompt_field(prompt, Pcs1::Site.new, :ssh_key)

        site = Pcs1::Site.create(
          name: name,
          domain: domain,
          timezone: timezone,
          ssh_key: ssh_key
        )

        view.show(site, **view_options(options))
      end
    end

    class Show < self
      desc "Show site details"

      def call(**options)
        site = Pcs1::Site.first
        unless site
          warn "Error: No site configured. Run 'pcs1 site add' first."
          exit 1
        end

        view.show(site, **view_options(options))
      end
    end

    class Update < self
      desc "Update site settings"

      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(field: nil, value: nil, **options)
        site = Pcs1::Site.first
        unless site
          warn "Error: No site configured. Run 'pcs1 site add' first."
          exit 1
        end

        if field && value
          site.update(field.to_sym => value)
          puts "Site: #{field} = #{value}"
        else
          prompt = TTY::Prompt.new
          site.name     = prompt_field(prompt, site, :name)
          site.domain   = prompt_field(prompt, site, :domain)
          site.timezone = prompt_field(prompt, site, :timezone)
          site.ssh_key  = prompt_field(prompt, site, :ssh_key)
          site.save!

          view.show(site, **view_options(options))
        end
      end
    end
  end
end
