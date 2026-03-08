# frozen_string_literal: true

require 'json'

module Pim
  class VmRunner
    class Error < StandardError; end

    attr_reader :vm, :ssh_port, :image_path, :instance_name

    def initialize(build:, name: nil)
      @build = build
      @profile = build.resolved_profile
      @arch = build.arch
      @name = name || build.id
      @vm = nil
      @ssh_port = nil
      @image_path = nil
      @golden_image = nil
      @temp_efi_vars = nil
      @bridged = false
      @bridge = nil
      @mac = nil
      @bridge_ip = nil
      @ga_socket = nil
      @registry = nil
      @instance_name = nil
    end

    # Boot the VM.
    #
    # Options:
    #   snapshot:  true (default) -- QEMU -snapshot, no disk changes
    #   clone:     false -- if true, full independent copy
    #   console:   false -- if true, attach serial to terminal (foreground)
    #   memory:    override from build recipe
    #   cpus:      override from build recipe
    #   bridged:   false -- if true, use bridged networking (VM gets LAN IP)
    #   bridge:    nil -- bridge device name (Linux only, default: br0)
    #
    # When snapshot: false and clone: false, creates a CoW overlay.
    # When clone: true, creates a full independent copy.
    # When snapshot: true (default), boots read-only with -snapshot.
    def run(snapshot: true, clone: false, console: false, memory: nil, cpus: nil,
            bridged: false, bridge: nil)
      @snapshot = snapshot
      @bridged = bridged
      @bridge = bridge
      @golden_image = find_golden_image
      @image_path = prepare_image(@golden_image, snapshot: snapshot, clone: clone)

      if bridged
        @ssh_port = nil
        builder = build_qemu_command(
          memory: memory || @build.memory,
          cpus: cpus || @build.cpus,
          snapshot: snapshot,
          bridged: true,
          bridge: bridge
        )
        cmd = builder.build
        cmd = ['sudo'] + cmd if macos?
        @vm = Pim::QemuVM.new(command: cmd, ssh_port: nil)
      else
        @ssh_port = Pim::Qemu.find_available_port
        builder = build_qemu_command(
          memory: memory || @build.memory,
          cpus: cpus || @build.cpus,
          snapshot: snapshot
        )
        @vm = Pim::QemuVM.new(command: builder.build, ssh_port: @ssh_port)
      end

      if console
        register_vm(snapshot: snapshot)
        print_connection_info
        @vm.start_console(detach: false)
        @vm.wait_for_exit
        unregister_vm
      else
        @vm.start_background
        register_vm(snapshot: snapshot)
        if bridged
          @bridge_ip = discover_ip(timeout: 30)
          @registry&.update(@instance_name, bridge_ip: @bridge_ip) if @bridge_ip
        end
        print_connection_info
      end

      self
    end

    # Register the current image as a provisioned variant in the image registry.
    # Call after successful provisioning.
    def register_image(label:, script:)
      raise Error, "Cannot register: no image path" unless @image_path
      raise Error, "Cannot register: image is a snapshot (ephemeral)" if @snapshot

      parent_id = "#{@profile.id}-#{@arch}"
      final_name = "#{parent_id}-#{label}.qcow2"
      final_path = File.join(File.dirname(@image_path), final_name)

      if @image_path != final_path
        FileUtils.mv(@image_path, final_path)
        old_efi = "#{@image_path}-efivars.fd"
        new_efi = "#{final_path}-efivars.fd"
        FileUtils.mv(old_efi, new_efi) if File.exist?(old_efi)
        @image_path = final_path
        @registry&.update(@instance_name, image_path: final_path)
      end

      registry = Pim::Registry.new
      registry.register_provisioned(
        parent_id: parent_id,
        label: label,
        path: final_path,
        script: script
      )
    end

    def stop
      @vm&.shutdown(timeout: 30)
      unregister_vm
      cleanup_efi_vars
    end

    def kill
      @vm&.kill
      cleanup_efi_vars
    end

    def running?
      @vm&.running? || false
    end

    # Upload and execute a script on the running VM.
    # Returns: { exit_code:, stdout:, stderr: }
    def provision(script_path, verbose: true, sudo: true)
      raise Error, "VM is not running" unless running?
      raise Error, "Script not found: #{script_path}" unless File.exist?(script_path)

      host, port = ssh_target
      raise Error, "Cannot determine SSH target" unless host

      puts "Waiting for SSH..."
      wait_for_ssh(host: host, port: port)

      puts "Uploading #{File.basename(script_path)}..."
      ssh = Pim::SSHConnection.new(
        host: host,
        port: port,
        user: @build.ssh_user,
        password: @profile.resolve('password')
      )

      remote_path = "/tmp/pim-provision-#{File.basename(script_path)}"
      ssh.upload(script_path, remote_path)
      ssh.execute("chmod +x #{remote_path}", sudo: sudo)

      puts "Running #{File.basename(script_path)}..."
      if verbose
        exit_code = ssh.execute_stream(remote_path, sudo: sudo) do |type, data|
          case type
          when :stdout then $stdout.write(data)
          when :stderr then $stderr.write(data)
          end
        end
        { exit_code: exit_code, stdout: '', stderr: '' }
      else
        ssh.execute(remote_path, sudo: sudo)
      end
    end

    # Determine SSH target based on networking mode
    def ssh_target
      if @bridged
        ip = @bridge_ip || discover_ip(timeout: 60)
        ip ? [ip, 22] : [nil, nil]
      else
        ['127.0.0.1', @ssh_port]
      end
    end

    private

    def find_golden_image
      registry = Pim::Registry.new(image_dir: Pim.config.image_dir)
      entry = registry.find_legacy(profile: @profile.id, arch: @arch)

      unless entry
        raise Error, "No image found for #{@profile.id}-#{@arch}. Run 'pim build run #{@build.id}' first."
      end

      path = entry['path']
      unless File.exist?(path)
        raise Error, "Image file missing: #{path}"
      end

      path
    end

    def prepare_image(golden_image, snapshot:, clone:)
      return golden_image if snapshot

      vm_dir = File.join(Pim.data_home, 'vms')
      FileUtils.mkdir_p(vm_dir)
      timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
      dest = File.join(vm_dir, "#{@name}-#{timestamp}.qcow2")

      if clone
        puts "Cloning image (this may take a moment)..."
        Pim::QemuDiskImage.clone(golden_image, dest)
      else
        Pim::QemuDiskImage.create_overlay(golden_image, dest)
      end

      dest
    end

    def build_qemu_command(memory:, cpus:, snapshot:, bridged: false, bridge: nil)
      builder = Pim::QemuCommandBuilder.new(
        arch: @arch,
        memory: memory,
        cpus: cpus,
        display: false,
        serial: nil
      )

      builder.add_drive(@image_path, format: 'qcow2')

      if bridged
        builder.add_bridged_net(bridge: bridge)
        add_guest_agent_channel(builder)
      else
        builder.add_user_net(host_port: @ssh_port, guest_port: 22)
      end

      builder.extra_args('-snapshot') if snapshot
      setup_efi(builder) if @arch == 'arm64'

      builder
    end

    def add_guest_agent_channel(builder)
      runtime_dir = Pim::Qemu.runtime_dir
      @ga_socket = File.join(runtime_dir, "#{@name}.ga")

      builder.extra_args(
        '-device', 'virtio-serial-pci',
        '-chardev', "socket,path=#{@ga_socket},server=on,wait=off,id=ga0",
        '-device', 'virtserialport,chardev=ga0,name=org.qemu.guest_agent.0'
      )
    end

    def discover_ip(timeout: 30)
      return nil unless @ga_socket

      deadline = Time.now + timeout
      while Time.now < deadline
        begin
          cmd = macos? ? ['sudo', 'socat', '-', "UNIX-CONNECT:#{@ga_socket}"] :
                         ['socat', '-', "UNIX-CONNECT:#{@ga_socket}"]

          query = '{"execute":"guest-network-get-interfaces"}'
          output, status = Open3.capture2(*cmd, stdin_data: "#{query}\n")

          if status.success? && output.include?('"ip-address"')
            data = JSON.parse(output.lines.last)
            if data['return']
              data['return'].each do |iface|
                next if iface['name'] == 'lo'
                iface['ip-addresses']&.each do |addr|
                  if addr['ip-address-type'] == 'ipv4'
                    return addr['ip-address']
                  end
                end
              end
            end
          end
        rescue StandardError
          # Agent not ready yet
        end

        sleep 2
      end

      nil
    end

    def setup_efi(builder)
      efi_code = Pim::Qemu.find_efi_firmware
      efi_vars = @golden_image.sub(/\.qcow2$/, '-efivars.fd')

      return unless efi_code && File.exist?(efi_vars)

      @temp_efi_vars = "#{@image_path}-efivars.fd"
      FileUtils.cp(efi_vars, @temp_efi_vars)

      builder.extra_args(
        '-drive', "if=pflash,format=raw,file=#{efi_code},readonly=on",
        '-drive', "if=pflash,format=raw,file=#{@temp_efi_vars}"
      )
    end

    def print_connection_info
      puts "VM: #{@name}"
      puts "  PID:     #{@vm.pid}"
      puts "  Arch:    #{@arch}"
      puts "  Image:   #{@image_path}"

      if @bridged
        puts "  Network: bridged"
        if @bridge_ip
          puts "  IP:      #{@bridge_ip}"
          puts "  SSH:     ssh #{@build.ssh_user}@#{@bridge_ip}"
        else
          puts "  IP:      (not yet discovered — check 'arp -a' or router DHCP leases)"
        end
      else
        puts "  SSH:     ssh -p #{@ssh_port} #{@build.ssh_user}@localhost"
        puts "  Network: user (port forwarding)"
      end
    end

    def register_vm(snapshot:)
      @registry = Pim::VmRegistry.new
      @instance_name = @registry.register(
        name: @name,
        pid: @vm.pid,
        build_id: @build.id,
        image_path: @image_path,
        ssh_port: @ssh_port,
        network: @bridged ? 'bridged' : 'user',
        mac: @mac,
        snapshot: snapshot
      )
    end

    def unregister_vm
      @registry&.unregister(@instance_name) if @instance_name
    end

    def wait_for_ssh(host:, port:, timeout: 300)
      deadline = Time.now + timeout
      while Time.now < deadline
        begin
          Timeout.timeout(5) do
            socket = TCPSocket.new(host, port)
            banner = socket.gets
            socket.close
            return true if banner&.start_with?('SSH-')
          end
        rescue StandardError
          sleep 5
        end
      end
      raise Error, "Timed out waiting for SSH on #{host}:#{port}"
    end

    def cleanup_efi_vars
      FileUtils.rm_f(@temp_efi_vars) if @temp_efi_vars
    end

    def macos?
      RUBY_PLATFORM.include?('darwin')
    end
  end
end
