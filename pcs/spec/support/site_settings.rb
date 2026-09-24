# frozen_string_literal: true

# Settings for a site whose pcm volumes and SSH key live in the example's tmpdir.
module SiteSettings
  def settings
    @settings ||= Pcs::Settings.new.tap do |s|
      s.pcm_volumes_home = @tmpdir.join("volumes").to_s
      s.ssh.key_path = key_path
      s.ssh.known_hosts = @tmpdir.join("known_hosts").to_s
    end
  end

  def key_path
    @key_path ||= @tmpdir.join("id_ed25519").tap do |key|
      key.write("-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n-----END OPENSSH PRIVATE KEY-----\n")
      Pathname("#{key}.pub").write("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPublicPart me@laptop\n")
    end.to_s
  end

  # Stands in for Adapters::Download: records URLs, writes a marker.
  def downloads
    @downloads ||= []
  end

  def download
    lambda do |url, path|
      downloads << url
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "<#{File.basename(url)}>")
    end
  end

  def pcm_system
    @pcm_system ||= FakeSystem.new.on("pcm", "ps", stdout: "dnsmasq-dnsmasq-1\n")
  end

  def pcm
    Pcs::Adapters::Pcm.new(system: pcm_system)
  end

  def menu_file(mac_hex)
    @tmpdir.join("volumes/netboot/config/menus/MAC-#{mac_hex}.ipxe")
  end
end

# Stands in for Adapters::Ssh: records commands and logins, answers from a script.
class FakeSsh
  attr_reader :commands, :logins
  attr_accessor :reachable, :forgotten

  def initialize(reachable: [true])
    @commands = []
    @logins = []
    @reachable = reachable
    @forgotten = 0
  end

  # The factory operations take: ssh: fake.method(:connect)
  def connect(host, password: nil)
    @logins << [host.ssh_user, password]
    self
  end

  def run!(*argv)
    @commands << argv
    Pcs::Adapters::SystemCmd::Result.new(argv, "", "", 0)
  end

  def reachable? = @reachable.size > 1 ? @reachable.shift : @reachable.first
  def forget_host_key = @forgotten += 1
end

RSpec.configure { |c| c.include SiteSettings }
