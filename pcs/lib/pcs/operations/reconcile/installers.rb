# frozen_string_literal: true

module Pcs
  module Operations
    class Reconcile < Termino::Operation
      # The Debian installer for each architecture the hosts need (the
      # hosts', not the control plane's), with firmware added to its initrd.
      # Each file is fetched once; delete it to fetch it again.
      module Installers
        private

        def fetch_installers(targets)
          targets.uniq(&:installer_dir).each do |target|
            files(target).each { |url, path| fetch(url, path) }
            add_firmware(installer_dir(target)) if @settings.install.firmware
          end
        end

        # URL => local path.
        def files(target)
          dir = installer_dir(target)
          base = installer_url(target.codename, target.arch)
          files = { "#{base}/linux" => File.join(dir, "linux"), "#{base}/initrd.gz" => File.join(dir, "initrd.gz") }
          return files unless @settings.install.firmware

          files.merge(@settings.install.firmware_url => File.join(dir, "firmware.cpio.gz"))
        end

        def installer_dir(target)
          File.join(@settings.netboot.assets_dir, target.installer_dir)
        end

        def installer_url(codename, arch)
          "#{@settings.install.mirror}/dists/#{codename}/main/installer-#{arch}/current/images/netboot/" \
            "debian-installer/#{arch}"
        end

        def fetch(url, path)
          return if File.exist?(path)

          step("download #{url}") { @download.call(url, path) }
        end

        # initrd-firmware.gz = the installer's initrd + the firmware archive
        # (the kernel unpacks concatenated cpio archives in turn).
        def add_firmware(dir)
          initrd = File.join(dir, "initrd-firmware.gz")
          return if File.exist?(initrd)

          step("add firmware to #{initrd}") do
            concatenate(%w[initrd.gz firmware.cpio.gz].map { |f| File.join(dir, f) }, "#{initrd}.part")
            File.rename("#{initrd}.part", initrd)
          end
        end

        def concatenate(sources, target)
          File.open(target, "wb") do |out|
            sources.each { |source| File.open(source, "rb") { |io| IO.copy_stream(io, out) } }
          end
        end
      end
    end
  end
end
