# frozen_string_literal: true

require "pathname"
require_relative "e2e_root"
require "pcs/platform/arch"

module Pcs
  module E2E
    class QemuLauncher
      DEFAULT_DISK_SIZE = "10G"
      DEFAULT_RAM = "1024"
      DEFAULT_CPUS = "2"

      attr_reader :pid, :arch

      def initialize(
        arch: Platform::Arch.native,
        tap: TestBridge::TAP_NAME,
        system_cmd: Pcs::Adapters::SystemCmd.new
      )
        @arch = arch
        @arch_config = Platform::Arch.config_for(arch)
        @tap = tap
        @cmd = system_cmd
        @pid = nil
      end

      def start_pxe(name: "pcs-e2e-node", ram: DEFAULT_RAM, cpus: DEFAULT_CPUS,
                     disk_size: DEFAULT_DISK_SIZE, no_reboot: false)
        prepare_disk(name, disk_size)

        args = base_args(name, ram, cpus) + [
          "-boot", "n",
          "-drive", "file=#{disk_path(name)},format=qcow2,if=virtio"
        ]
        args << "-no-reboot" if no_reboot

        launch(args)
      end

      def start_disk(name: "pcs-e2e-node", ram: DEFAULT_RAM, cpus: DEFAULT_CPUS)
        args = base_args(name, ram, cpus) + [
          "-boot", "c",
          "-drive", "file=#{disk_path(name)},format=qcow2,if=virtio"
        ]

        launch(args)
      end

      def stop
        return unless @pid

        Process.kill("TERM", @pid)
        Process.wait(@pid)
        @pid = nil
      rescue Errno::ESRCH, Errno::ECHILD
        @pid = nil
      end

      def running?
        return false unless @pid

        Process.kill(0, @pid)
        true
      rescue Errno::ESRCH
        false
      end

      def wait_for_exit(timeout: 600)
        raise "No QEMU process to wait for" unless @pid

        deadline = Time.now + timeout
        loop do
          raise Timeout::Error, "QEMU did not exit within #{timeout}s" if Time.now > deadline

          result = Process.waitpid(@pid, Process::WNOHANG)
          if result
            @pid = nil
            return true
          end

          sleep 10
        end
      rescue Errno::ECHILD
        @pid = nil
        true
      end

      def cleanup_disk(name: "pcs-e2e-node")
        path = disk_path(name)
        path.delete if path.exist?
      end

      private

      def base_args(name, ram, cpus)
        accel = Platform::Arch.kvm_available?(@arch) ? "kvm" : "tcg"
        cpu = accel == "kvm" ? @arch_config[:cpu_kvm] : @arch_config[:cpu_tcg]

        args = [
          @arch_config[:qemu_binary],
          "-name", name,
          "-machine", "#{@arch_config[:machine]},accel=#{accel}",
          "-cpu", cpu,
          "-m", ram,
          "-smp", cpus,
          "-nographic",
          "-serial", "mon:stdio",
          "-nic", "tap,ifname=#{@tap},script=no,downscript=no,model=#{@arch_config[:nic_model]}"
        ]

        # arm64 virt machine requires explicit UEFI firmware
        if @arch_config[:uefi_firmware]
          args += ["-bios", @arch_config[:uefi_firmware]]
        end

        args
      end

      def prepare_disk(name, size)
        DIRS[:disk].mkpath
        path = disk_path(name)
        return if path.exist?

        result = @cmd.run!("qemu-img create -f qcow2 #{path} #{size}")
        raise "Failed to create disk: #{result.stderr}" unless result.success?
      end

      def disk_path(name)
        DIRS[:disk] / "#{name}.qcow2"
      end

      def launch(args)
        log_path = DIRS[:logs] / "qemu.log"
        DIRS[:logs].mkpath

        @pid = Process.spawn(
          *args,
          in: "/dev/null",
          out: log_path.to_s,
          err: log_path.to_s
        )

        sleep 2

        unless running?
          raise "QEMU failed to start. Check #{log_path}"
        end

        @pid
      end
    end
  end
end
