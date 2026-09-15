# frozen_string_literal: true

require 'json'
require 'socket'

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
      @disk = nil
      @snapshot = false
      @bridged = false
      @bridge = nil
      @usb_devices = []
      @sudo = false
      @mac = nil
      @bridge_ip = nil
      @ga_socket = nil
      @registry = nil
      @instance_name = nil
    end

    # Boot the VM.
    #
    # Options:
    #   disk:     'clone'    -- persistent full copy in vms/<name>.qcow2, reused on later runs
    #             'overlay'  -- persistent thin copy (backed by the built image)
    #             'snapshot' -- QEMU -snapshot, nothing is saved
    #   network:  'bridged'  -- VM gets a LAN IP (QEMU runs under sudo on macOS)
    #             'host'     -- NAT with SSH port forwarding
    #   bridge:   interface to bridge (macOS default: default-route interface, Linux: br0)
    #   usb:      USB disks to pass through ("VID:PID" on macOS, or device paths)
    #   fresh:    recreate a persistent disk from the built image
    #   console:  attach serial to terminal (foreground)
    #   memory:   override from build recipe
    #   cpus:     override from build recipe
    def run(disk: 'clone', network: 'bridged', bridge: nil, usb: [], fresh: false,
            console: false, memory: nil, cpus: nil)
      validate_options!(disk, network)

      @disk = disk
      @snapshot = disk == 'snapshot'
      @bridged = network == 'bridged'
      @bridge = bridge || (macos? ? Pim::Qemu.default_interface : nil) if @bridged
      @golden_image = find_golden_image
      @image_path = @snapshot ? @golden_image : persistent_image_path
      ensure_disk_not_in_use!

      # Resolve USB disks before any slow disk copy so a missing stick fails fast
      @usb_devices = Array(usb).map { |spec| Pim::UsbDisk.resolve(spec) }
      @sudo = (macos? && (@bridged || @usb_devices.any?)) ||
              @usb_devices.any? { |device| !File.writable?(device) }

      prepare_image(fresh: fresh)
      @usb_devices.each { |device| Pim::UsbDisk.release(device) }
      @ssh_port = @bridged ? nil : Pim::Qemu.find_available_port

      builder = build_qemu_command(memory: memory || @build.memory, cpus: cpus || @build.cpus)
      cmd = builder.build
      if @sudo
        authenticate_sudo!
        # -n: never prompt from the background (stdin is /dev/null); fails fast into the log instead
        cmd = ['sudo', '-n'] + cmd
      end
      @vm = Pim::QemuVM.new(command: cmd, ssh_port: @ssh_port)

      if console
        register_vm
        print_connection_info
        @vm.start_console(detach: false)
        @vm.wait_for_exit
        unregister_vm
      else
        @log_path = File.join(Pim::Qemu.runtime_dir, "#{@name}.log")
        puts "Starting VM (QEMU output: #{@log_path})"
        @vm.start_background(log_path: @log_path)
        register_vm
        if @bridged
          claim_agent_socket
          @bridge_ip = discover_ip(timeout: 60)
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

    def validate_options!(disk, network)
      unless Pim::VmSettings::DISKS.include?(disk)
        raise Error, "Unknown disk mode '#{disk}' (use: #{Pim::VmSettings::DISKS.join(', ')})"
      end
      return if Pim::VmSettings::NETWORKS.include?(network)

      raise Error, "Unknown network '#{network}' (use: #{Pim::VmSettings::NETWORKS.join(', ')})"
    end

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

    # One persistent disk per VM name, so later runs pick up where the last one left off
    def persistent_image_path
      File.join(Pim.data_home, 'vms', "#{@name}.qcow2")
    end

    # Two QEMUs writing the same disk would corrupt it
    def ensure_disk_not_in_use!
      return if @snapshot

      in_use = Pim::VmRegistry.new.list.find { |vm| vm['image_path'] == @image_path }
      return unless in_use

      raise Error, "VM disk #{@image_path} is in use by '#{in_use['name']}' " \
                   "(stop it first, or use --name for a separate VM)"
    end

    def prepare_image(fresh:)
      return if @snapshot

      if File.exist?(@image_path) && !fresh
        puts "Using existing VM disk: #{@image_path} (--fresh to start over from the built image)"
        return
      end

      FileUtils.rm_f([@image_path, "#{@image_path}-efivars.fd"])
      FileUtils.mkdir_p(File.dirname(@image_path))

      if @disk == 'clone'
        puts "Cloning image (this may take a moment)..."
        Pim::QemuDiskImage.clone(@golden_image, @image_path)
      else
        Pim::QemuDiskImage.create_overlay(@golden_image, @image_path)
      end
    end

    def build_qemu_command(memory:, cpus:)
      builder = Pim::QemuCommandBuilder.new(
        arch: @arch,
        memory: memory,
        cpus: cpus,
        display: false,
        serial: nil
      )

      builder.add_drive(@image_path, format: 'qcow2')

      if @bridged
        builder.add_bridged_net(bridge: @bridge)
        add_guest_agent_channel(builder)
      else
        builder.add_user_net(host_port: @ssh_port, guest_port: 22)
      end

      @usb_devices.each { |device| builder.add_usb_disk(Pim::UsbDisk.qemu_path(device)) }

      builder.extra_args('-snapshot') if @snapshot
      setup_efi(builder) if @arch == 'arm64'

      builder
    end

    # Prompt for the sudo password up front, while the terminal is still ours
    def authenticate_sudo!
      reasons = []
      reasons << 'bridged networking' if @bridged
      reasons << 'USB passthrough' if @usb_devices.any?
      puts "sudo is needed for #{reasons.join(' and ')}"
      raise Error, 'sudo authentication failed' unless system('sudo', '-v')
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

    # Polls the guest agent for the VM's first IPv4 address, showing progress while the guest boots
    def discover_ip(timeout: 30)
      return nil unless @ga_socket

      print "Waiting for the VM's IP from the guest agent (up to #{timeout}s)"
      $stdout.flush
      deadline = Time.now + timeout

      while Time.now < deadline
        unless @vm.running?
          puts
          raise Error, "VM exited while booting#{log_tail}"
        end

        ip = query_guest_ip
        if ip
          puts " #{ip}"
          return ip
        end

        print '.'
        $stdout.flush
        sleep 2
      end

      puts ' no IP yet'
      nil
    end

    # QEMU under sudo creates the agent socket as root; take ownership once so it can be queried
    # directly (no `sudo socat`, whose stdin never reaches EOF under sudo's pty and hangs)
    def claim_agent_socket
      return unless @sudo && @ga_socket

      10.times do
        break if File.socket?(@ga_socket)

        sleep 0.5
      end
      system('sudo', '-n', 'chown', Process.uid.to_s, @ga_socket, out: File::NULL, err: File::NULL)
    end

    def query_guest_ip
      response = UNIXSocket.open(@ga_socket) do |sock|
        sock.write(%({"execute":"guest-network-get-interfaces"}\n))
        read_agent_reply(sock, timeout: 3)
      end
      return nil unless response

      data = JSON.parse(response)
      (data['return'] || []).each do |iface|
        next if iface['name'] == 'lo'

        iface['ip-addresses']&.each do |addr|
          return addr['ip-address'] if addr['ip-address-type'] == 'ipv4'
        end
      end
      nil
    rescue StandardError
      nil # agent not ready yet
    end

    # First complete `"return"` line from the guest agent, or nil if none arrives within timeout
    def read_agent_reply(sock, timeout:)
      buffer = +''
      deadline = Time.now + timeout

      while (remaining = deadline - Time.now).positive?
        return nil unless IO.select([sock], nil, nil, remaining)

        chunk = sock.read_nonblock(65_536, exception: false)
        return nil if chunk.nil? # agent side closed
        next if chunk == :wait_readable

        buffer << chunk
        line = buffer.each_line.find { |l| l.end_with?("\n") && l.include?('"return"') }
        return line if line
      end

      nil
    end

    # Last lines of the QEMU log, for error messages
    def log_tail
      return '' unless @log_path && File.exist?(@log_path)

      tail = File.readlines(@log_path).last(15).join.strip
      tail.empty? ? " (no QEMU output in #{@log_path})" : ":\n#{tail}"
    end

    # Snapshot VMs get a throwaway copy of the EFI vars; persistent disks keep theirs alongside
    def setup_efi(builder)
      efi_code = Pim::Qemu.find_efi_firmware
      golden_vars = @golden_image.sub(/\.qcow2$/, '-efivars.fd')

      return unless efi_code && File.exist?(golden_vars)

      vars = "#{@image_path}-efivars.fd"
      FileUtils.cp(golden_vars, vars) if @snapshot || !File.exist?(vars)
      @temp_efi_vars = vars if @snapshot

      builder.extra_args(
        '-drive', "if=pflash,format=raw,file=#{efi_code},readonly=on",
        '-drive', "if=pflash,format=raw,file=#{vars}"
      )
    end

    def print_connection_info
      puts "VM: #{@name}"
      puts "  PID:     #{@vm.pid}"
      puts "  Arch:    #{@arch}"
      puts "  Disk:    #{@disk} (#{@image_path})"
      @usb_devices.each { |device| puts "  USB:     #{device}" }

      if @bridged
        puts "  Network: bridged (#{@bridge || 'br0'})"
        if @bridge_ip
          puts "  IP:      #{@bridge_ip}"
          puts "  SSH:     ssh #{@build.ssh_user}@#{@bridge_ip}"
        else
          puts "  IP:      (not yet discovered — check 'arp -a' or router DHCP leases)"
        end
      else
        puts "  SSH:     ssh -p #{@ssh_port} #{@build.ssh_user}@localhost"
        puts "  Network: host (port forwarding)"
      end
    end

    def register_vm
      @registry = Pim::VmRegistry.new
      @instance_name = @registry.register(
        name: @name,
        pid: @vm.pid,
        build_id: @build.id,
        image_path: @image_path,
        ssh_port: @ssh_port,
        network: @bridged ? 'bridged' : 'host',
        mac: @mac,
        disk: @disk,
        sudo: @sudo,
        usb: @usb_devices
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
