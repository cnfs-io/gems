# frozen_string_literal: true

require 'time'

module Pim
  VerifyResult = Struct.new(:success, :exit_code, :stdout, :stderr, :duration, keyword_init: true)

  class Verifier
    class VerifyError < StandardError; end

    DEFAULT_VERIFY_TIMEOUT = 300 # 5 minutes — image is pre-built, should boot fast

    def initialize(build:)
      @build = build
      @profile = build.resolved_profile
      @arch = build.arch
      @vm = nil
      @ssh_port = nil
      @temp_efi_vars = nil
      @console_log_path = nil
    end

    # Options:
    #   verbose:       print verification script output
    #   console_log:   path to write serial console output (for debugging boot issues)
    #   ssh_timeout:   seconds to wait for SSH (default: 300)
    def verify(verbose: false, console_log: nil, ssh_timeout: DEFAULT_VERIFY_TIMEOUT)
      @console_log_path = console_log
      start_time = Time.now

      # Touch the console log so `tail -f` works immediately
      if @console_log_path
        FileUtils.touch(@console_log_path)
        output "Console log ready: #{@console_log_path}"
      end

      begin
        # 1. Find image
        image_path = find_image
        output "Image: #{image_path}"

        # 2. Find verification script
        script_path = find_verification_script
        output "Verification script: #{File.basename(script_path)}"

        # 3. Boot VM in snapshot mode
        boot_vm_snapshot(image_path)
        output "VM booted (PID: #{@vm.pid}, SSH port: #{@ssh_port})"
        output "Console log: #{@console_log_path}" if @console_log_path

        # 4. Wait for SSH
        output "Waiting for SSH (timeout: #{ssh_timeout}s)..."
        wait_for_ssh(ssh_timeout)

        # 5. Upload and run verification script
        output "Running verification script..."
        result = run_verification_script(script_path, verbose: verbose)

        # 6. Shutdown
        shutdown_vm

        duration = Time.now - start_time
        VerifyResult.new(
          success: result[:exit_code] == 0,
          exit_code: result[:exit_code],
          stdout: result[:stdout],
          stderr: result[:stderr],
          duration: duration
        )
      rescue StandardError => e
        cleanup
        duration = Time.now - start_time
        VerifyResult.new(
          success: false,
          exit_code: -1,
          stdout: "",
          stderr: e.message,
          duration: duration
        )
      end
    end

    private

    def image_dir
      Pim.config.image_dir
    end

    def memory
      @build.memory
    end

    def cpus
      @build.cpus
    end

    def ssh_user
      @build.ssh_user
    end

    def output(msg)
      puts "  #{msg}"
    end

    def find_image
      registry = Pim::Registry.new(image_dir: image_dir)
      entry = registry.find_legacy(profile: @profile.id, arch: @arch)

      unless entry
        raise VerifyError, "No image found for #{@profile.id}-#{@arch}. Run 'pim build run' first."
      end

      path = entry['path']
      unless File.exist?(path)
        raise VerifyError, "Image file missing: #{path}"
      end

      path
    end

    def find_verification_script
      script = @profile.verification_script
      unless script
        raise VerifyError, "No verification script for profile '#{@profile.id}'. " \
                           "Create resources/verifications/#{@profile.id}.sh or resources/verifications/default.sh"
      end
      script
    end

    def boot_vm_snapshot(image_path)
      @ssh_port = Pim::Qemu.find_available_port

      builder = Pim::QemuCommandBuilder.new(
        arch: @arch,
        memory: memory,
        cpus: cpus,
        display: false,
        serial: nil
      )

      builder.add_drive(image_path, format: 'qcow2')
      builder.add_user_net(host_port: @ssh_port, guest_port: 22)
      builder.extra_args('-snapshot')  # CRITICAL: don't modify the image

      # EFI vars for arm64
      if @arch == 'arm64'
        efi_code = Pim::Qemu.find_efi_firmware
        efi_vars = image_path.sub(/\.qcow2$/, '-efivars.fd')

        if efi_code && File.exist?(efi_vars)
          # Copy vars to temp file since -snapshot doesn't apply to pflash
          @temp_efi_vars = "#{efi_vars}.verify-tmp"
          FileUtils.cp(efi_vars, @temp_efi_vars)

          builder.extra_args(
            '-drive', "if=pflash,format=raw,file=#{efi_code},readonly=on",
            '-drive', "if=pflash,format=raw,file=#{@temp_efi_vars}"
          )
        end
      end

      @vm = Pim::QemuVM.new(command: builder.build, ssh_port: @ssh_port)

      # -nographic sends serial to stdout. Redirect stdout to log file
      # instead of /dev/null so we can see what the VM is doing.
      if @console_log_path
        @vm.start_background_with_log(@console_log_path, detach: false)
      else
        @vm.start_background(detach: false)
      end
    end

    def wait_for_ssh(timeout)
      timeout = Integer(timeout)
      success = @vm.wait_for_ssh(timeout: timeout, poll_interval: 5)
      raise VerifyError, "Timed out waiting for SSH (#{timeout}s)" unless success
      sleep 3  # give services a moment to settle
    end

    def run_verification_script(script_path, verbose: false)
      ssh = Pim::SSHConnection.new(
        host: '127.0.0.1',
        port: @ssh_port,
        user: ssh_user,
        password: @profile.resolve('password')
      )

      remote_path = '/tmp/pim-verify.sh'
      ssh.upload(script_path, remote_path)
      ssh.execute("chmod +x #{remote_path}", sudo: true)
      result = ssh.execute(remote_path, sudo: true)

      if verbose
        puts result[:stdout] unless result[:stdout].strip.empty?
        $stderr.puts result[:stderr] unless result[:stderr].strip.empty?
      end

      result
    end

    def shutdown_vm
      return unless @vm&.running?

      begin
        ssh = Pim::SSHConnection.new(
          host: '127.0.0.1',
          port: @ssh_port,
          user: ssh_user,
          password: @profile.resolve('password')
        )
        ssh.execute('shutdown -h now', sudo: true)
        sleep 3
      rescue StandardError
        # SSH may fail during shutdown
      end

      @vm.shutdown(timeout: 30)
    ensure
      cleanup_efi_vars
    end

    def cleanup
      @vm&.kill if @vm&.running?
      cleanup_efi_vars
    end

    def cleanup_efi_vars
      FileUtils.rm_f(@temp_efi_vars) if @temp_efi_vars
    end
  end
end
