# frozen_string_literal: true

module Pim
  class TargetsCommand < RestCli::Command
    class List < self
      desc "List all deploy targets"

      def call(**options)
        view.list(Pim::Target.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show target information"

      argument :id, required: true, desc: "Target ID"

      def call(id:, **options)
        target = Pim::Target.find(id)
        view.show(target, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Target '#{id}' not found")
      end
    end

    class Update < self
      desc "Update a deploy target"

      argument :id, required: true, desc: "Target ID"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id:, field: nil, value: nil, **)
        target = Pim::Target.find(id)

        if field && value
          direct_set(target, field, value)
        else
          interactive_update(target)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Target '#{id}' not found")
      end

      private

      def direct_set(target, field, value)
        target.update(field.to_sym => value)
        puts "Target #{target.id}: #{field} = #{value}"
      end

      def interactive_update(target)
        prompt = TTY::Prompt.new

        target.name      = prompt_field(prompt, target, :name)
        target.type      = prompt_field(prompt, target, :type)
        target.parent_id = prompt_field(prompt, target, :parent_id)

        target.save!
        puts "Target #{target.id} updated."
      end
    end

    class Add < self
      desc "Add a new deploy target"

      def call(**)
        puts "Target creation is not yet implemented."
        puts "Manually add a YAML file to data/targets/ in your project directory."
      end
    end

    class Remove < self
      desc "Remove a deploy target"

      argument :id, required: true, desc: "Target ID"

      def call(id:, **)
        puts "Target removal is not yet implemented."
        puts "Manually delete the target YAML file from data/targets/ in your project directory."
      end
    end
  end
end
