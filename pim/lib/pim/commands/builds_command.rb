# frozen_string_literal: true

module Pim
  class BuildsCommand < RestCli::Command
    class List < self
      desc "List build recipes"

      def call(**options)
        view.list(Pim::Build.all, **view_options(options))
      end
    end

    class Show < self
      desc "Show build recipe information"

      argument :id, required: true, desc: "Build recipe ID"

      def call(id:, **options)
        build = Pim::Build.find(id)
        view.show(build, **view_options(options))
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Build '#{id}' not found")
      end
    end

    class Run < self
      desc "Build an image from a build recipe"

      argument :build_id, required: true, desc: "Build recipe ID"

      option :force, type: :boolean, default: false, aliases: ["-f"], desc: "Force rebuild ignoring cache"
      option :dry_run, type: :boolean, default: false, aliases: ["-n"], desc: "Show what would be done"
      option :vnc, type: :integer, default: nil, desc: "Enable VNC display on port 5900+N"
      option :console, type: :boolean, default: false, aliases: ["-c"], desc: "Stream serial console output to stdout"
      option :console_log, type: :string, default: nil, desc: "Log serial console to file"

      def call(build_id:, force: false, dry_run: false, vnc: nil, console: false, console_log: nil, **)
        require_relative "../build/manager"

        build = Pim::Build.find(build_id)
        manager = Pim::BuildManager.new

        if dry_run
          manager.dry_run_build(build)
        else
          manager.execute_build(
            build,
            force: force,
            vnc: vnc,
            console: console,
            console_log: console_log
          )
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Build '#{build_id}' not found")
      end
    end

    class Clean < self
      desc "Clean cached images"

      option :orphaned, type: :boolean, default: false, desc: "Only remove orphaned registry entries"
      option :all, type: :boolean, default: false, desc: "Remove all cached images"

      def call(orphaned: false, all: false, **)
        registry = Pim::Registry.new(image_dir: Pim.config.image_dir)

        if orphaned
          removed = registry.clean_orphaned
          if removed.empty?
            puts 'No orphaned entries found'
          else
            puts "Removed #{removed.size} orphaned entries:"
            removed.each { |key| puts "  - #{key}" }
          end
        elsif all
          print "Remove all images in #{Pim.config.image_dir}? (y/N) "
          response = $stdin.gets.chomp
          return unless response.downcase == 'y'

          entries = registry.list
          entries.each do |entry|
            FileUtils.rm_f(entry[:path]) if entry[:path] && File.exist?(entry[:path])
            registry.unregister(profile: entry[:profile], arch: entry[:arch])
          end
          puts "Removed #{entries.size} images"
        else
          puts 'Use --orphaned to clean orphaned entries or --all to remove all images'
        end
      end
    end

    class Status < self
      desc "Show build system status"

      def call(**)
        resolver = Pim::ArchitectureResolver.new

        puts 'Build System Status'
        puts
        puts "Host architecture: #{resolver.host_arch}"
        puts "Image directory:   #{Pim.config.image_dir}"
        puts
        puts 'Builders:'

        %w[arm64 x86_64].each do |arch|
          can_local = resolver.can_build_locally?(arch)
          status = can_local ? 'local (available)' : 'local (unavailable - wrong arch)'
          puts "  #{arch}: #{status}"
        end

        registry = Pim::Registry.new(image_dir: Pim.config.image_dir)
        images = registry.list
        puts
        puts "Cached images: #{images.size}"
      end
    end

    class Update < self
      desc "Update a build recipe"

      argument :id, required: true, desc: "Build recipe ID"
      argument :field, required: false, desc: "Field name"
      argument :value, required: false, desc: "New value"

      def call(id:, field: nil, value: nil, **)
        build = Pim::Build.find(id)

        if field && value
          direct_set(build, field, value)
        else
          interactive_update(build)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Error: Build '#{id}' not found")
      end

      private

      def direct_set(build, field, value)
        build.update(field.to_sym => value)
        puts "Build #{build.id}: #{field} = #{value}"
      end

      def interactive_update(build)
        prompt = TTY::Prompt.new

        build.profile    = prompt_field(prompt, build, :profile)
        build.iso        = prompt_field(prompt, build, :iso)
        build.distro     = prompt_field(prompt, build, :distro)
        build.arch       = prompt_field(prompt, build, :arch)
        build.target     = prompt_field(prompt, build, :target)
        build.disk_size  = prompt_field(prompt, build, :disk_size)
        build.memory     = prompt_field(prompt, build, :memory)
        build.cpus       = prompt_field(prompt, build, :cpus)
        build.ssh_user   = prompt_field(prompt, build, :ssh_user)
        build.ssh_timeout = prompt_field(prompt, build, :ssh_timeout)

        build.save!
        puts "Build #{build.id} updated."
      end
    end

    class Verify < self
      desc "Verify a built image by running its verification script"

      argument :build_id, required: true, desc: "Build recipe ID"

      option :verbose, type: :boolean, default: false, aliases: ["-v"], desc: "Show verification script output"
      option :console_log, type: :string, desc: "Write serial console to file (for debugging)"
      option :console, type: :boolean, default: false, desc: "Boot VM with interactive console (for manual debugging)"
      option :ssh_timeout, type: :integer, default: Pim::Verifier::DEFAULT_VERIFY_TIMEOUT,
             desc: "Seconds to wait for SSH (default: #{Pim::Verifier::DEFAULT_VERIFY_TIMEOUT})"

      def call(build_id:, verbose: false, console_log: nil, console: false, ssh_timeout: Pim::Verifier::DEFAULT_VERIFY_TIMEOUT, **)
        build = Pim::Build.find(build_id)

        if console
          boot_interactive(build)
          return
        end

        profile = build.resolved_profile

        puts "Verifying: #{build_id}"
        puts "  Profile: #{profile.id}"
        puts "  Arch:    #{build.arch}"
        puts "  Console: #{console_log}" if console_log
        puts

        verifier = Pim::Verifier.new(build: build)
        result = verifier.verify(verbose: verbose, console_log: console_log, ssh_timeout: ssh_timeout)

        puts
        if result.success
          puts "OK Verification passed (#{format_duration(result.duration)})"
        else
          puts "FAIL Verification failed (exit code: #{result.exit_code})"
          unless result.stderr.strip.empty?
            puts
            puts "Error output:"
            puts result.stderr
          end
          Pim.exit!(1)
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Build '#{build_id}' not found")
      end

      private

      def boot_interactive(build)
        puts "Booting VM in interactive console mode (Ctrl+A X to quit QEMU)"
        puts "  Build:   #{build.id}"
        puts "  Profile: #{build.resolved_profile.id}"
        puts "  Arch:    #{build.arch}"
        puts

        runner = Pim::VmRunner.new(build: build)
        runner.run(snapshot: true, console: true)
      end

      def format_duration(seconds)
        if seconds < 60
          "#{seconds.round(1)}s"
        else
          "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
        end
      end
    end
  end
end
