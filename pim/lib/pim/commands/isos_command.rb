# frozen_string_literal: true

module Pim
  class IsosCommand < RestCli::Command
    class List < self
      desc "List all ISOs in catalog"

      def call(**options)
        view.list(Pim::Iso.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show ISO information"

      argument :id, required: true, desc: "ISO key"

      def call(id:, **options)
        iso = Pim::Iso.find(id)
        view.show(iso, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: ISO '#{id}' not found")
      end
    end

    class Download < self
      desc "Download a specific ISO from catalog"

      argument :iso_key, required: false, desc: "ISO key to download"

      option :all, type: :boolean, default: false, aliases: ["-a"], desc: "Download all missing ISOs"

      def call(iso_key: nil, all: false, **)
        if all
          download_all
        elsif iso_key
          iso = Pim::Iso.find(iso_key)
          iso.download
        else
          puts "Error: Provide an ISO key or use --all flag"
          Pim.exit!(1)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: ISO '#{iso_key}' not found in catalog")
      end

      private

      def download_all
        isos = Pim::Iso.all
        missing = isos.reject(&:downloaded?)

        if missing.empty?
          puts 'All ISOs are already downloaded.'
          return
        end

        puts "Downloading missing ISOs...\n\n"
        success_count = 0
        missing.each_with_index do |iso, idx|
          puts "[#{idx + 1}/#{missing.size}] Downloading #{iso.id}..."
          Pim::HTTP.download(iso.url, iso.iso_path.to_s)
          if iso.verify(silent: true)
            puts "OK Downloaded and verified\n\n"
            success_count += 1
          else
            puts "FAIL Checksum verification failed\n\n"
          end
        end
        puts "Summary: #{success_count} ISOs downloaded successfully"
      end
    end

    class Verify < self
      desc "Verify checksum of a downloaded ISO"

      argument :iso_key, required: false, desc: "ISO key to verify"

      option :all, type: :boolean, default: false, aliases: ["-a"], desc: "Verify all downloaded ISOs"

      def call(iso_key: nil, all: false, **)
        if all
          verify_all
        elsif iso_key
          iso = Pim::Iso.find(iso_key)
          iso.verify
        else
          puts "Error: Provide an ISO key or use --all flag"
          Pim.exit!(1)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: ISO '#{iso_key}' not found in catalog")
      end

      private

      def verify_all
        isos = Pim::Iso.all
        downloaded = isos.select(&:downloaded?)

        if downloaded.empty?
          puts 'No downloaded ISOs to verify.'
          return
        end

        puts "Verifying downloaded ISOs...\n\n"
        passed = 0
        failed = 0
        downloaded.each do |iso|
          result = iso.verify(silent: true)
          fname = iso.filename || "#{iso.id}.iso"
          status = result ? 'OK' : 'FAIL Checksum mismatch'
          puts "#{fname.ljust(35)} #{status}"
          result ? passed += 1 : failed += 1
        end
        puts
        puts "Summary: #{passed} passed, #{failed} failed"
      end
    end

    class Update < self
      desc "Update an ISO"

      argument :id, required: true, desc: "ISO key"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id:, field: nil, value: nil, **)
        iso = Pim::Iso.find(id)

        if field && value
          direct_set(iso, field, value)
        else
          interactive_update(iso)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: ISO '#{id}' not found")
      end

      private

      def direct_set(iso, field, value)
        iso.update(field.to_sym => value)
        puts "ISO #{iso.id}: #{field} = #{value}"
      end

      def interactive_update(iso)
        prompt = TTY::Prompt.new

        iso.name         = prompt_field(prompt, iso, :name)
        iso.architecture = prompt_field(prompt, iso, :architecture)
        iso.url          = prompt_field(prompt, iso, :url)
        iso.checksum     = prompt_field(prompt, iso, :checksum)
        iso.checksum_url = prompt_field(prompt, iso, :checksum_url)
        iso.filename     = prompt_field(prompt, iso, :filename)

        iso.save!
        puts "ISO #{iso.id} updated."
      end
    end

    class Add < self
      desc "Add a new ISO to the catalog interactively"

      def call(**)
        puts "ISO add requires write support (not yet available with read-only FlatRecord)."
        puts "Manually add entries to isos.yml in your project directory."
      end
    end

    class Remove < self
      desc "Remove an ISO from the catalog"

      argument :id, required: true, desc: "ISO key"

      def call(id:, **)
        puts "ISO removal is not yet implemented."
        puts "Manually delete the ISO YAML file from data/isos/ in your project directory."
      end
    end
  end
end
