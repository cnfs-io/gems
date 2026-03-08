# frozen_string_literal: true

module Pim
  class VmCommand < RestCli::Command
    class Run < self
      desc "Boot a VM from a built image"

      argument :build_id, required: true, desc: "Build recipe ID (e.g., default-arm64)"

      option :console, type: :boolean, default: false, aliases: ["-c"],
             desc: "Attach serial console (foreground, Ctrl+A X to quit)"
      option :snapshot, type: :boolean, default: true,
             desc: "Boot read-only, discard changes on exit (default)"
      option :clone, type: :boolean, default: false,
             desc: "Create a full independent copy of the image"
      option :bridged, type: :boolean, default: false,
             desc: "Use bridged networking (VM gets LAN IP, requires sudo on macOS)"
      option :bridge, type: :string, default: nil,
             desc: "Bridge device for bridged networking (default: br0, Linux only)"
      option :name, type: :string, default: nil,
             desc: "Name for this VM instance (default: build_id)"
      option :memory, type: :integer, default: nil,
             desc: "Override memory in MB"
      option :cpus, type: :integer, default: nil,
             desc: "Override CPU count"
      option :run, type: :string, default: nil,
             desc: "Script to upload and execute after boot (shuts down VM after)"
      option :run_and_stay, type: :string, default: nil,
             desc: "Script to upload and execute after boot (keeps VM running)"
      option :label, type: :string, default: nil,
             desc: "Label for the provisioned image (required when images.require_label is true)"

      def call(build_id:, console: false, snapshot: true, clone: false,
               bridged: false, bridge: nil, name: nil, memory: nil, cpus: nil,
               run: nil, run_and_stay: nil, label: nil, **)
        if run && run_and_stay
          Pim.exit!(1, message: "Cannot use both --run and --run-and-stay")
          return
        end

        script_path = run || run_and_stay
        shutdown_after = !!run

        if script_path && !File.exist?(script_path)
          Pim.exit!(1, message: "Script not found: #{script_path}")
          return
        end

        # Resolve label for provisioning
        if script_path
          label = resolve_label(label, script_path)
          return unless label
        end

        build = Pim::Build.find(build_id)

        # --clone implies --no-snapshot
        snapshot = false if clone

        # --run/--run-and-stay implies --no-snapshot (changes should persist)
        if script_path && snapshot && !clone
          puts "Note: --run implies --no-snapshot (changes will persist in a CoW overlay)"
          snapshot = false
        end

        runner = Pim::VmRunner.new(build: build, name: name || build_id)

        if script_path
          runner.run(
            snapshot: snapshot, clone: clone, console: false,
            memory: memory, cpus: cpus, bridged: bridged, bridge: bridge
          )

          result = runner.provision(script_path, verbose: true)

          if result[:exit_code] == 0
            puts "\nProvisioning complete (exit code 0)"

            image = runner.register_image(label: label, script: script_path)
            puts "Image registered: #{image.id}"
          else
            puts "\nProvisioning failed (exit code #{result[:exit_code]})"
            puts "Image NOT registered (provisioning must succeed to track)"
          end

          if shutdown_after
            puts "Shutting down VM..."
            runner.stop
          else
            puts "VM is still running."
            puts "Stop with: pim vm stop #{runner.instance_name}"
          end
        else
          runner.run(
            snapshot: snapshot, clone: clone, console: console,
            memory: memory, cpus: cpus, bridged: bridged, bridge: bridge
          )

          unless console
            puts
            puts "VM is running in the background."
            puts "Stop with: pim vm stop #{runner.instance_name}  (or kill PID #{runner.vm.pid})"
          end
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Build '#{build_id}' not found")
      rescue Pim::VmRunner::Error => e
        Pim.exit!(1, message: e.message)
      end

      private

      def resolve_label(label, script_path)
        if label
          unless label.match?(/\A[a-z0-9][a-z0-9\-]*\z/)
            Pim.exit!(1, message: "Invalid label '#{label}'. Use lowercase alphanumeric and hyphens.")
            return nil
          end
          label
        elsif Pim.config.images.require_label
          Pim.exit!(1, message: "--run requires --label to track the provisioned image.\n" \
                                "Set config.images.require_label = false in pim.rb to auto-generate labels.")
          nil
        else
          File.basename(script_path, '.*')
              .gsub(/[^a-z0-9\-]/, '-')
              .gsub(/-+/, '-')
              .gsub(/\A-|-\z/, '')
        end
      end
    end

    class List < self
      desc "List running VMs"

      def call(**)
        registry = Pim::VmRegistry.new
        vms = registry.list

        if vms.empty?
          puts "No running VMs."
          return
        end

        puts format("%-4s %-25s %-8s %-10s %-30s",
                    "#", "NAME", "PID", "NETWORK", "SSH")
        puts "-" * 80

        vms.each_with_index do |vm, idx|
          ssh_info = case vm['network']
                     when 'bridged'
                       ip = vm['bridge_ip']
                       ip ? "ssh #{ssh_user(vm)}@#{ip}" : "MAC: #{vm['mac']}"
                     else
                       "ssh -p #{vm['ssh_port']} #{ssh_user(vm)}@localhost"
                     end

          puts format("%-4s %-25s %-8s %-10s %-30s",
                      idx + 1, vm['name'], vm['pid'], vm['network'], ssh_info)
        end
      end

      private

      def ssh_user(vm)
        build = Pim::Build.find(vm['build_id'])
        build.ssh_user
      rescue FlatRecord::RecordNotFound
        "ansible"
      end
    end

    class Stop < self
      desc "Stop a running VM"

      argument :identifier, required: true, desc: "VM number (from 'vm list') or name"

      option :force, type: :boolean, default: false, aliases: ["-f"],
             desc: "Force kill instead of graceful shutdown"

      def call(identifier:, force: false, **)
        registry = Pim::VmRegistry.new
        vm = registry.find(identifier)

        unless vm
          Pim.exit!(1, message: "VM '#{identifier}' not found. Run 'pim vm list' to see running VMs.")
          return
        end

        pid = vm['pid']
        name = vm['name']

        begin
          if force
            if vm['network'] == 'bridged' && macos?
              system('sudo', 'kill', '-9', pid.to_s)
            else
              Process.kill('KILL', pid)
            end
            puts "Killed VM '#{name}' (PID #{pid})"
          else
            if vm['network'] == 'bridged' && macos?
              system('sudo', 'kill', '-TERM', pid.to_s)
            else
              Process.kill('TERM', pid)
            end
            puts "Shutting down VM '#{name}' (PID #{pid})..."
            wait_for_exit(pid, timeout: 30)
          end
        rescue Errno::ESRCH
          puts "VM '#{name}' is already stopped."
        end

        registry.unregister(name)
        cleanup_vm_files(vm)
      end

      private

      def macos?
        RUBY_PLATFORM.include?('darwin')
      end

      def wait_for_exit(pid, timeout: 30)
        deadline = Time.now + timeout
        while Time.now < deadline
          begin
            Process.kill(0, pid)
            sleep 1
          rescue Errno::ESRCH, Errno::EPERM
            return true
          end
        end
        false
      end

      def cleanup_vm_files(vm)
        efi_vars = "#{vm['image_path']}-efivars.fd"
        FileUtils.rm_f(efi_vars) if File.exist?(efi_vars)
      end
    end

    class Ssh < self
      desc "SSH into a running VM"

      argument :identifier, required: true, desc: "VM number (from 'vm list') or name"

      def call(identifier:, **)
        registry = Pim::VmRegistry.new
        vm = registry.find(identifier)

        unless vm
          Pim.exit!(1, message: "VM '#{identifier}' not found. Run 'pim vm list' to see running VMs.")
          return
        end

        build = Pim::Build.find(vm['build_id'])
        host, port = ssh_target(vm)

        unless host
          Pim.exit!(1, message: "Cannot determine SSH target for VM '#{vm['name']}'. " \
                                 "For bridged VMs, the IP may not have been discovered yet.")
          return
        end

        ssh_cmd = ['ssh',
                   '-o', 'StrictHostKeyChecking=no',
                   '-o', 'UserKnownHostsFile=/dev/null',
                   '-o', 'LogLevel=ERROR']
        ssh_cmd += ['-p', port.to_s] if port != 22
        ssh_cmd << "#{build.ssh_user}@#{host}"

        exec(*ssh_cmd)
      end

      private

      def ssh_target(vm)
        if vm['network'] == 'bridged' && vm['bridge_ip']
          [vm['bridge_ip'], 22]
        elsif vm['ssh_port']
          ['127.0.0.1', vm['ssh_port']]
        else
          [nil, nil]
        end
      end
    end
  end
end
