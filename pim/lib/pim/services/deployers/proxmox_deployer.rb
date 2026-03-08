# frozen_string_literal: true

module Pim
  class ProxmoxDeployer
    class Error < StandardError; end

    DEFAULT_MEMORY = 2048
    DEFAULT_CORES = 2

    def initialize(target:, image:, build: nil)
      @target = target
      @image = image
      @build = build
      @ssh = nil
    end

    def deploy(vm_id: nil, name: nil, memory: nil, cores: nil, cpus: nil, dry_run: false, **)
      validate!

      cores ||= cpus
      vm_id ||= next_vm_id
      name ||= template_name
      memory ||= @build&.respond_to?(:memory) ? @build.memory : DEFAULT_MEMORY
      cores ||= @build&.respond_to?(:cpus) ? @build.cpus : DEFAULT_CORES
      storage = @target.storage || 'local-lvm'
      bridge = @target.bridge || 'vmbr0'
      node = @target.node

      remote_path = "/tmp/pim-deploy-#{@image.id}.qcow2"

      steps = [
        "Upload #{@image.filename} to #{@target.host}:#{remote_path}",
        "qm create #{vm_id} --name #{name} --memory #{memory} --cores #{cores} --net0 virtio,bridge=#{bridge}",
        "qm importdisk #{vm_id} #{remote_path} #{storage}",
        "qm set #{vm_id} --scsi0 #{storage}:vm-#{vm_id}-disk-0 --scsihw virtio-scsi-pci",
        "qm set #{vm_id} --boot order=scsi0",
        "qm set #{vm_id} --serial0 socket --vga serial0",
        "qm template #{vm_id}",
        "rm #{remote_path}"
      ]

      if dry_run
        puts "Dry run -- would execute:"
        steps.each_with_index { |s, i| puts "  #{i + 1}. #{s}" }
        return { vm_id: vm_id, name: name, dry_run: true }
      end

      connect_ssh!

      puts "Uploading #{@image.filename} to #{@target.host}..."
      upload_image(remote_path)

      puts "Creating VM #{vm_id} (#{name})..."
      ssh_exec("qm create #{vm_id} --name #{name} --memory #{memory} --cores #{cores} " \
               "--net0 virtio,bridge=#{bridge}")

      puts "Importing disk to #{storage}..."
      output = ssh_exec("qm importdisk #{vm_id} #{remote_path} #{storage}")
      disk_ref = parse_disk_ref(output, vm_id, storage)

      puts "Attaching disk..."
      ssh_exec("qm set #{vm_id} --scsi0 #{disk_ref} --scsihw virtio-scsi-pci")

      ssh_exec("qm set #{vm_id} --boot order=scsi0")
      ssh_exec("qm set #{vm_id} --serial0 socket --vga serial0")

      puts "Converting to template..."
      ssh_exec("qm template #{vm_id}")

      ssh_exec("rm -f #{remote_path}")

      puts "Deployed as template #{vm_id} (#{name}) on #{@target.host}"

      { vm_id: vm_id, name: name, node: node, storage: storage }
    end

    private

    def validate!
      raise Error, "Image file missing: #{@image.path}" unless @image.exists?

      unless @image.published? || @image.golden?
        raise Error, "Image '#{@image.id}' must be published before deploying to Proxmox.\n" \
                     "Run: pim image publish #{@image.id}"
      end

      raise Error, "Target host not configured" unless @target.host
      raise Error, "Target node not configured" unless @target.node
    end

    def connect_ssh!
      @ssh = Pim::SSHConnection.new(
        host: @target.host,
        port: 22,
        user: 'root',
        key_file: ssh_key_path
      )
    end

    def ssh_key_path
      key = @target.respond_to?(:ssh_key) ? @target.ssh_key : nil
      key || File.expand_path('~/.ssh/id_rsa')
    end

    def upload_image(remote_path)
      @ssh.upload(@image.path, remote_path)
    end

    def ssh_exec(command)
      result = @ssh.execute(command, sudo: false)
      unless result[:exit_code] == 0
        stderr = result[:stderr].strip
        raise Error, "Command failed: #{command}\n#{stderr}"
      end
      result[:stdout]
    end

    def next_vm_id
      start = @target.vm_id_start || 9000
      begin
        connect_ssh! unless @ssh
        result = @ssh.execute("qm list 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n | tail -1")
        max_existing = result[:stdout].strip.to_i
        [start, max_existing + 1].max
      rescue StandardError
        start
      end
    end

    def template_name
      label = @image.label
      if label
        "pim-#{@image.profile}-#{label}"
      else
        "pim-#{@image.id}"
      end
    end

    def parse_disk_ref(output, vm_id, storage)
      if output =~ /imported disk as '([^']+)'/
        $1
      else
        "#{storage}:vm-#{vm_id}-disk-0"
      end
    end
  end
end
