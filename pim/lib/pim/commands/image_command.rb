# frozen_string_literal: true

module Pim
  class ImageCommand < RestCli::Command
    class List < self
      desc "List all tracked images"

      option :status, type: :string, default: nil,
             desc: "Filter by status (built, verified, provisioned, published)"

      def call(status: nil, **)
        registry = Pim::Registry.new
        images = registry.all

        images = images.select { |i| i.status == status } if status

        if images.empty?
          puts "No images found."
          return
        end

        puts format("%-4s %-30s %-12s %-14s %-20s %-8s %-8s",
                    "#", "ID", "STATUS", "LABEL", "PARENT", "SIZE", "AGE")
        puts "-" * 100

        images.each_with_index do |img, idx|
          label = img.label || (img.golden? ? "golden" : "-")
          parent = img.parent_id || "-"
          size = img.human_size || "?"
          age = img.age || "?"

          puts format("%-4s %-30s %-12s %-14s %-20s %-8s %-8s",
                      idx + 1, img.id, img.status, label, parent, size, age)
        end
      end
    end

    class Show < self
      desc "Show detailed image information"

      argument :id, required: true, desc: "Image ID"

      def call(id:, **)
        registry = Pim::Registry.new
        image = registry.find(id)

        unless image
          Pim.exit!(1, message: "Image '#{id}' not found. Run 'pim image list' to see available images.")
          return
        end

        puts "Image: #{image.id}"
        puts
        puts "  Profile:      #{image.profile}"
        puts "  Arch:         #{image.arch}"
        puts "  Status:       #{image.status}"
        puts "  Label:        #{image.label || '-'}"
        puts "  Path:         #{image.path}"
        puts "  Exists:       #{image.exists? ? 'yes' : 'NO (missing!)'}"
        puts "  Size:         #{image.human_size || '?'}"
        puts "  ISO:          #{image.iso || '-'}"
        puts "  Built:        #{image.build_time || '-'}"
        puts "  Cache key:    #{image.cache_key || '-'}"

        if image.parent_id
          puts
          puts "  Lineage"
          puts "  Parent:       #{image.parent_id}"
          puts "  Provisioned:  #{image.provisioned_with || '-'}"
          puts "  Prov. time:   #{image.provisioned_at || '-'}"
        end

        if image.published_at
          puts
          puts "  Published:    #{image.published_at}"
        end

        unless image.deployments.empty?
          puts
          puts "  Deployments (#{image.deployments.size}):"
          image.deployments.each do |d|
            puts "    -> #{d['target']} (#{d['target_type']}) at #{d['deployed_at']}"
          end
        end
      end
    end

    class Delete < self
      desc "Delete an image from registry and disk"

      argument :id, required: true, desc: "Image ID"

      option :force, type: :boolean, default: false, aliases: ["-f"],
             desc: "Skip confirmation"
      option :keep_file, type: :boolean, default: false,
             desc: "Remove from registry but keep the file on disk"

      def call(id:, force: false, keep_file: false, **)
        registry = Pim::Registry.new
        image = registry.find(id)

        unless image
          Pim.exit!(1, message: "Image '#{id}' not found.")
          return
        end

        children = registry.all.select { |i| i.parent_id == id }
        unless children.empty?
          puts "Warning: #{children.size} image(s) depend on this image as a backing file:"
          children.each { |c| puts "  - #{c.id}" }
          puts
          puts "Deleting this image will make those overlays unusable."
          puts "Delete children first, or publish them (which flattens the overlay)."
          Pim.exit!(1) unless force
        end

        unless force
          print "Delete image '#{id}'? "
          print "(file will be kept) " if keep_file
          print "(y/N) "
          response = $stdin.gets.chomp
          return unless response.downcase == 'y'
        end

        if !keep_file && image.path && File.exist?(image.path)
          FileUtils.rm_f(image.path)
          efi_vars = image.path.sub(/\.qcow2$/, '-efivars.fd')
          FileUtils.rm_f(efi_vars) if File.exist?(efi_vars)
          puts "Deleted file: #{image.path}"
        end

        registry.delete(id)
        puts "Removed '#{id}' from registry."
      end
    end

    class Publish < self
      desc "Publish an image (flatten overlay to standalone qcow2)"

      argument :id, required: true, desc: "Image ID"

      option :compress, type: :boolean, default: false, aliases: ["-c"],
             desc: "Compress the output image"
      option :output, type: :string, default: nil, aliases: ["-o"],
             desc: "Output path (default: replaces overlay in place)"

      def call(id:, compress: false, output: nil, **)
        registry = Pim::Registry.new
        image = registry.find(id)

        unless image
          Pim.exit!(1, message: "Image '#{id}' not found.")
          return
        end

        unless image.exists?
          Pim.exit!(1, message: "Image file missing: #{image.path}")
          return
        end

        case image.status
        when 'published'
          puts "Image '#{id}' is already published."
          return
        when 'built', 'verified'
          if golden_standalone?(image.path)
            registry.update_status(id, 'published')
            puts "Published '#{id}' (already standalone, status updated)."
            return
          end
        end

        if output
          dest = File.expand_path(output)
        else
          dest = "#{image.path}.publish-tmp"
        end

        puts "Publishing '#{id}'..."
        puts "  Source:     #{image.path}"
        puts "  Compress:   #{compress}"

        disk = Pim::QemuDiskImage.new(image.path)
        begin
          disk.convert(dest, format: 'qcow2', compress: compress)
        rescue Pim::QemuDiskImage::Error => e
          FileUtils.rm_f(dest) if dest.end_with?('.publish-tmp')
          Pim.exit!(1, message: "Publish failed: #{e.message}")
          return
        end

        unless output
          original = image.path
          FileUtils.mv(dest, original)
          dest = original
        end

        # Update path if output was specified
        if output
          raw_images = registry.instance_variable_get(:@data)['images']
          raw_images[id]['path'] = dest
          raw_images[id]['filename'] = File.basename(dest)
        end
        registry.update_status(id, 'published')

        final_size = File.exist?(dest) ? File.size(dest) : 0
        original_size = image.size || 0
        puts "  Output:     #{dest}"
        puts "  Size:       #{format_size(final_size)} (was #{format_size(original_size)})"
        puts "Published '#{id}' successfully."
      end

      private

      def golden_standalone?(path)
        disk = Pim::QemuDiskImage.new(path)
        info = disk.info
        !info.key?('backing-filename')
      rescue StandardError
        true
      end

      def format_size(bytes)
        return "?" unless bytes && bytes > 0

        if bytes > 1_073_741_824
          format("%.1fG", bytes.to_f / 1_073_741_824)
        elsif bytes > 1_048_576
          format("%.1fM", bytes.to_f / 1_048_576)
        else
          format("%.1fK", bytes.to_f / 1024)
        end
      end
    end

    class Deploy < self
      desc "Deploy an image to a target"

      argument :image_id, required: true, desc: "Image ID"
      argument :target_id, required: true, desc: "Target ID (from 'pim target list')"

      option :vm_id, type: :integer, default: nil,
             desc: "Specific VM ID (Proxmox only, default: auto)"
      option :name, type: :string, default: nil,
             desc: "Template/instance name (default: auto from image)"
      option :memory, type: :integer, default: nil,
             desc: "Memory in MB (default: from build recipe)"
      option :cpus, type: :integer, default: nil,
             desc: "CPU cores (default: from build recipe)"
      option :dry_run, type: :boolean, default: false, aliases: ["-n"],
             desc: "Show what would be done without doing it"

      def call(image_id:, target_id:, vm_id: nil, name: nil, memory: nil, cpus: nil, dry_run: false, **)
        registry = Pim::Registry.new
        image = registry.find(image_id)

        unless image
          Pim.exit!(1, message: "Image '#{image_id}' not found. Run 'pim image list'.")
          return
        end

        target = Pim::Target.find(target_id)

        if image.overlay? && !image.published?
          if Pim.config.images.auto_publish
            puts "Auto-publishing overlay before deploy..."
            publish_image(registry, image_id)
            image = registry.find(image_id)
          else
            Pim.exit!(1, message: "Image '#{image_id}' is an overlay and must be published first.\n" \
                                  "Run: pim image publish #{image_id}\n" \
                                  "Or set config.images.auto_publish = true in pim.rb")
            return
          end
        end

        build = resolve_build(image)

        puts "Deploying '#{image_id}' to '#{target_id}' (#{target.class.name.split('::').last})..."
        begin
          result = target.deploy(image, build: build,
                                 vm_id: vm_id, name: name,
                                 memory: memory, cpus: cpus,
                                 dry_run: dry_run)
        rescue StandardError => e
          Pim.exit!(1, message: e.message)
          return
        end

        unless dry_run
          registry.record_deployment(
            image_id,
            target: target_id,
            target_type: target.type,
            metadata: result.slice(:vm_id, :name, :node).transform_keys(&:to_s)
          )
        end
      rescue FlatRecord::RecordNotFound
        Pim.exit!(1, message: "Target '#{target_id}' not found. Run 'pim target list'.")
      end

      private

      def resolve_build(image)
        build_id = "#{image.profile}-#{image.arch}"
        Pim::Build.find(build_id)
      rescue FlatRecord::RecordNotFound
        Pim::Build.find(image.profile) rescue nil
      end

      def publish_image(registry, image_id)
        image = registry.find!(image_id)
        disk = Pim::QemuDiskImage.new(image.path)
        temp = "#{image.path}.publish-tmp"
        disk.convert(temp, format: 'qcow2')
        FileUtils.mv(temp, image.path)
        registry.update_status(image_id, 'published')
      end
    end
  end
end
