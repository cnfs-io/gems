# frozen_string_literal: true

module Pim
  class ProfilesCommand < RestCli::Command
    class List < self
      desc "List all profiles"

      def call(**options)
        view.list(Pim::Profile.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show profile information"

      argument :id, required: true, desc: "Profile name"

      def call(id:, **options)
        profile = Pim::Profile.find(id)
        view.show(profile, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Profile '#{id}' not found")
      end
    end

    class Update < self
      desc "Update a profile"

      argument :id, required: true, desc: "Profile name"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id:, field: nil, value: nil, **)
        profile = Pim::Profile.find(id)

        if field && value
          direct_set(profile, field, value)
        else
          interactive_update(profile)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Profile '#{id}' not found")
      end

      private

      def direct_set(profile, field, value)
        profile.update(field.to_sym => value)
        puts "Profile #{profile.id}: #{field} = #{value}"
      end

      def interactive_update(profile)
        prompt = TTY::Prompt.new

        profile.parent_id = prompt_field(prompt, profile, :parent_id)
        profile.hostname  = prompt_field(prompt, profile, :hostname)
        profile.username  = prompt_field(prompt, profile, :username)
        profile.fullname  = prompt_field(prompt, profile, :fullname)
        profile.timezone  = prompt_field(prompt, profile, :timezone)
        profile.domain    = prompt_field(prompt, profile, :domain)
        profile.locale    = prompt_field(prompt, profile, :locale)
        profile.keyboard  = prompt_field(prompt, profile, :keyboard)
        profile.packages  = prompt_field(prompt, profile, :packages)

        profile.save!
        puts "Profile #{profile.id} updated."
      end
    end

    class Add < self
      desc "Add a new profile"

      def call(**)
        puts "Profile add requires write support (not yet available with read-only FlatRecord)."
        puts "Manually add entries to profiles.yml in your project directory."
      end
    end

    class Remove < self
      desc "Remove a profile"

      argument :id, required: true, desc: "Profile name"

      def call(id:, **)
        puts "Profile removal is not yet implemented."
        puts "Manually delete the profile YAML file from data/profiles/ in your project directory."
      end
    end
  end
end
