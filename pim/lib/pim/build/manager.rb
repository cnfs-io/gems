# frozen_string_literal: true

require_relative 'local_builder'

module Pim
  # Build manager - orchestrates the build process
  class BuildManager
    def initialize
      @resolver = Pim::ArchitectureResolver.new
      @cache = Pim::CacheManager.new(project_dir: Pim.project_dir)
      @script_loader = Pim::ScriptLoader.new(project_dir: Pim.project_dir)
    end

    # Execute a build from a Build model record
    def execute_build(build, force: false, vnc: nil, console: false, console_log: nil)
      profile = build.resolved_profile
      iso = build.resolved_iso
      arch = @resolver.normalize(build.arch)
      profile_name = profile.id

      puts "Building #{build.id} (#{profile_name} for #{arch})"
      puts

      # Check dependencies
      check_dependencies!

      # Verify architecture
      profile_data = profile.to_h
      verify_architecture(profile_data, arch)

      # Select builder
      builder_info = @resolver.select_builder(arch)

      # Resolve ISO path
      iso_key = iso.id
      filepath = iso.iso_path

      unless filepath.exist?
        puts "ISO not downloaded: #{iso_key}"
        puts "Run: pim iso download #{iso_key}"
        Pim.exit!(1)
      end

      iso_path = filepath.to_s
      iso_checksum = iso.checksum || ''

      # Resolve scripts
      script_names = profile_data['scripts'] || %w[base finalize]
      scripts = resolve_scripts(script_names)

      # Calculate cache key
      cache_key = @cache.cache_key(
        profile_data: profile_data,
        scripts: scripts,
        iso_checksum: iso_checksum,
        arch: arch
      )

      puts "Build:      #{build.id}"
      puts "Profile:    #{profile_name}"
      puts "Arch:       #{arch}"
      puts "Distro:     #{build.distro}"
      puts "Automation: #{build.automation}"
      puts "Builder:    #{builder_info[:type]}"
      puts "ISO:        #{iso_key}"
      puts "Scripts:    #{script_names.join(', ')}"
      puts "Cache key:  #{cache_key}"
      puts "VNC:        :#{vnc} (localhost:#{5900 + vnc})" if vnc
      puts "Console:    stdout" if console && !console_log
      puts "Console:    #{console_log}" if console_log
      puts

      # Check cache
      unless force
        if cached = @cache.cached_image(profile: profile_name, arch: arch, cache_key: cache_key)
          puts "Cache hit: #{cached}"
          puts "Use --force to rebuild"
          return cached
        end
      end

      # Execute build based on builder type
      case builder_info[:type]
      when :local
        local_build(
          build: build,
          profile: profile,
          profile_name: profile_name,
          arch: arch,
          iso_key: iso_key,
          iso_path: iso_path,
          cache_key: cache_key,
          scripts: scripts,
          vnc: vnc,
          console: console,
          console_log: console_log
        )
      when :remote
        remote_build(
          builder_info: builder_info,
          profile: profile,
          profile_name: profile_name,
          arch: arch,
          iso_key: iso_key,
          cache_key: cache_key,
          scripts: scripts
        )
      else
        raise "Unknown builder type: #{builder_info[:type]}"
      end
    end

    # Dry run from a Build model record
    def dry_run_build(build)
      profile = build.resolved_profile
      iso = build.resolved_iso
      arch = @resolver.normalize(build.arch)
      profile_name = profile.id

      puts "Dry run: #{build.id} (#{profile_name} for #{arch})"
      puts

      # Check dependencies
      missing = Pim::Qemu.check_dependencies
      if missing.any?
        puts "Missing dependencies: #{missing.join(', ')}"
        puts "(would fail)"
        puts
      end

      profile_data = profile.to_h

      # Verify architecture
      architectures = profile_data['architectures']
      if architectures && !architectures.include?(arch)
        puts "Warning: #{arch} not in profile's architectures: #{architectures.join(', ')}"
      end

      # Select builder
      builder_info = @resolver.select_builder(arch)

      # ISO info
      iso_key = iso.id
      iso_path = iso.iso_path
      iso_checksum = iso.checksum || ''

      # Resolve scripts
      script_names = profile_data['scripts'] || %w[base finalize]
      begin
        scripts = resolve_scripts(script_names)
      rescue StandardError => e
        puts "Warning: #{e.message}"
        scripts = []
      end

      # Calculate cache key
      cache_key = @cache.cache_key(
        profile_data: profile_data,
        scripts: scripts,
        iso_checksum: iso_checksum,
        arch: arch
      )

      # Effective build config
      disk = build.disk_size
      mem = build.memory
      cpu = build.cpus

      puts "Configuration:"
      puts "  Build:        #{build.id}"
      puts "  Profile:      #{profile_name}"
      puts "  Architecture: #{arch}"
      puts "  Distro:       #{build.distro}"
      puts "  Automation:   #{build.automation}"
      puts "  Build method: #{build.build_method}"
      puts "  Builder:      #{builder_info[:type]}#{builder_info[:name] ? " (#{builder_info[:name]})" : ''}"
      puts "  Image dir:    #{Pim.config.image_dir}"
      puts "  Disk size:    #{disk}"
      puts "  Memory:       #{mem} MB"
      puts "  CPUs:         #{cpu}"
      puts

      puts "ISO:"
      puts "  Key:      #{iso_key}"
      puts "  Path:     #{iso_path}"
      puts "  Exists:   #{iso_path.exist? ? 'yes' : 'NO - will need download'}"
      puts "  Checksum: #{iso_checksum[0..40]}..."
      puts

      puts "Scripts (#{scripts.size}):"
      script_names.each_with_index do |name, i|
        path = scripts[i] rescue nil
        status = path ? (File.exist?(path) ? 'OK' : 'MISSING') : 'NOT FOUND'
        puts "  #{name}: #{status}"
        puts "    #{path}" if path
      end
      puts

      puts "Cache:"
      puts "  Key: #{cache_key}"
      cached = @cache.cached_image(profile: profile_name, arch: arch, cache_key: cache_key)
      if cached
        puts "  Status: HIT - #{cached}"
        puts "  Would skip build (use --force to override)"
      else
        puts "  Status: MISS - will build"
      end
      puts

      puts "Build steps:"
      puts "  1. Create disk image (#{disk})"
      puts "  2. Start preseed server"
      puts "  3. Start QEMU with ISO boot"
      puts "  4. Wait for SSH (timeout: #{build.ssh_timeout}s)"
      puts "  5. Run provisioning scripts"
      puts "  6. Finalize image (clean cloud-init, truncate machine-id)"
      puts "  7. Shutdown VM"
      puts "  8. Register in registry"
    end

    private

    def check_dependencies!
      missing = Pim::Qemu.check_dependencies
      return if missing.empty?

      puts "Missing dependencies: #{missing.join(', ')}"
      puts "Install with: brew install qemu"
      Pim.exit!(1)
    end

    def verify_architecture(profile_data, arch)
      architectures = profile_data['architectures']
      return unless architectures

      unless architectures.include?(arch)
        puts "Error: Profile does not support #{arch}"
        puts "Supported architectures: #{architectures.join(', ')}"
        Pim.exit!(1)
      end
    end

    def resolve_scripts(script_names)
      @script_loader.resolve_scripts(script_names)
    end

    def local_build(build:, profile:, profile_name:, arch:, iso_key:, iso_path:, cache_key:, scripts:,
                     vnc: nil, console: false, console_log: nil)
      builder = Pim::LocalBuilder.new(
        build: build,
        profile: profile,
        profile_name: profile_name,
        arch: arch,
        iso_path: iso_path,
        iso_key: iso_key
      )

      builder.build(cache_key: cache_key, scripts: scripts, vnc: vnc, console: console, console_log: console_log)
    end

    def remote_build(builder_info:, profile:, profile_name:, arch:, iso_key:, cache_key:, scripts:)
      puts "Remote builds not yet implemented"
      puts "Builder: #{builder_info[:name]}"
      puts "Host: #{builder_info[:config]['host']}"
      Pim.exit!(1)
    end
  end
end
