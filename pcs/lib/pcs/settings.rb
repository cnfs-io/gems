# frozen_string_literal: true

require "termino/settings"

# :nodoc:
module Pcs
  # Settings each site project can override in its pcs.rb:
  #
  #   Pcs.configure do |settings|
  #     settings.dnsmasq.mode = "dhcp"
  #     settings.install.password_hash = "$6$..."
  #   end
  class Settings < Termino::Settings
    # Where pcm lets containers read and write host files. The dnsmasq and
    # netboot containers (installed by the pcs ppm package, run by pcm) mount
    # their directories from here, so pcs writes their config here too.
    setting :pcm_volumes_home, default: lambda {
      ENV.fetch("PCM_VOLUMES_HOME") do
        File.join(ENV.fetch("XDG_DATA_HOME") { File.join(Dir.home, ".local", "share") }, "pcm", "volumes")
      end
    }

    group :ssh do
      # The private key pcs connects to hosts with; only its .pub is ever copied to them.
      setting :key_path, default: -> { File.join(Dir.home, ".ssh", "id_ed25519") }
      # Host keys are trusted on first use and pinned here.
      setting :known_hosts, default: -> { File.join(Termino::Project.root || Dir.pwd, "ssh", "known_hosts") }
    end

    group :scan do
      # nmap only reports MAC addresses when run as root.
      setting :sudo, default: true
    end

    group :dnsmasq do
      # The pcm service name.
      setting :service, default: "dnsmasq"
      # "proxy": answer PXE requests only, leaving addresses to the site's DHCP
      # server. "dhcp": serve DHCP too, with a reservation per configured host.
      setting :mode, default: "proxy"
      setting :config_dir, default: -> { File.join(parent.pcm_volumes_home, service, "dnsmasq.d") }
    end

    group :netboot do
      setting :service, default: "netboot"
      # Where the netboot container serves assets_dir over HTTP.
      setting :http_port, default: 8080
      # Seconds a host's boot menu waits before its default (disk, or install).
      setting :menu_timeout, default: 5
      setting :menus_dir, default: -> { File.join(parent.pcm_volumes_home, service, "config", "menus") }
      setting :assets_dir, default: -> { File.join(parent.pcm_volumes_home, service, "assets") }
    end

    group :install do
      # The admin user a PXE install creates, and pcs connects as.
      setting :user, default: "pcs"
      # A crypt(3) SHA-512 hash (mkpasswd -m sha-512) for that user; nil means
      # no password login, key only. Plaintext passwords are never used.
      setting :password_hash, default: nil
      setting :debian_codename, default: "trixie"
      setting :mirror, default: "http://deb.debian.org/debian"
      # Add non-free firmware (for NICs that need it) to the installer's
      # initrd. Off by default: Debian's bundle for trixie is ~500 MB, which
      # the installer must hold in RAM. Point firmware_url at a smaller cpio
      # (just the NIC firmware a site needs) to turn it on cheaply.
      setting :firmware, default: false
      setting :firmware_url, default: lambda {
        "https://cdimage.debian.org/cdimage/firmware/#{debian_codename}/current/firmware.cpio.gz"
      }
      setting :locale, default: "en_US.UTF-8"
      setting :keymap, default: "us"
      # Installed on top of the standard system and an SSH server.
      setting :packages, default: %w[sudo curl]
      # Minutes an install may take, from asking for it to logging in.
      setting :timeout, default: 60
    end
  end

  extend Termino::Configurable
end
