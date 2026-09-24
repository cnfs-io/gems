# frozen_string_literal: true

RSpec.describe "host operations" do
  let(:ssh) { FakeSsh.new }
  let(:out) { StringIO.new }
  let(:common) { { settings:, ssh: ssh.method(:connect), reconcile: { pcm:, download: }, out: } }

  describe Pcs::Operations::Key do
    let(:kvm) { host(Pcs::PikvmHost, hostname: "kvm1", configured_ip: "10.0.0.20") }

    it "installs pcs's public key with the device's password, then logs in with the key" do
      op = described_class.new(host_id: kvm.id, password: "admin", **common).call!

      expect(ssh.logins).to eq([%w[root admin], ["root", nil]])
      install, check = ssh.commands
      expect(install.first(2)).to eq(["sh", "-c"])
      expect(install[2]).to start_with("rw && ").and include('grep -qxF "$1"')
      expect(install.last).to eq("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPublicPart pcs")
      expect(check).to eq(["true"])
      expect(op.value.status).to eq("keyed")
      expect(Pcs::Host.find(kvm.id).status).to eq("keyed")
    end

    it "only checks the key when there's no password (it was added by hand)" do
      jet = host(Pcs::JetkvmHost, hostname: "jet1", mac: "aa:bb:cc:00:00:07", configured_ip: "10.0.0.21")
      described_class.new(host_id: jet.id, **common).call!
      expect(ssh.commands).to eq([["true"]])

      other = host(Pcs::JetkvmHost, hostname: "jet2", mac: "aa:bb:cc:00:00:08")
      op = described_class.new(host_id: other.id, password: "x", **common).call
      expect(op.error.message).to eq("add pcs's key in jet2's web UI, then key it without a password")
    end

    it "isn't for hosts pcs installs" do
      debian = host(Pcs::DebianHost, hostname: "n1")
      expect(described_class.new(host_id: debian.id, **common).call.error.message).to match(/configure it instead/)
    end
  end

  describe Pcs::Operations::Configure do
    it "says what's missing" do
      h = host(Pcs::DebianHost, hostname: "n1")
      expect(described_class.new(host_id: h.id, **common).call.error.message)
        .to eq("n1 still needs: configured ip, disk, control plane ip")
    end

    it "marks a complete host configured and writes its boot menu" do
      control_plane
      h = host(Pcs::DebianHost, hostname: "n1", disk: "/dev/sda", configured_ip: "10.0.0.11")
      op = described_class.new(host_id: h.id, **common).call!

      expect(Pcs::Host.find(h.id).status).to eq("configured")
      expect(op.value).to eq(h)
      expect(menu_file("aabbcc000001")).to exist
      expect(out.string).to include("→ mark n1 configured", "MAC-aabbcc000001.ipxe")
    end
  end

  describe Pcs::Operations::Install do
    let!(:node) do
      control_plane
      host(Pcs::DebianHost, hostname: "n1", disk: "/dev/sda", configured_ip: "10.0.0.11", status: "configured")
    end

    # Answers pings from a script; records the menu's default at each ping.
    let(:probe) do
      answers = pings
      defaults = menu_defaults
      menu = menu_file("aabbcc000001")
      Object.new.tap do |probe|
        probe.define_singleton_method(:ping?) do |_ip|
          defaults << menu.read[/--default (\w+)/, 1] if menu.exist?
          answers.size > 1 ? answers.shift : answers.first
        end
      end
    end
    let(:pings) { [false, false, true] }
    let(:menu_defaults) { [] }

    def install(**opts)
      described_class.new(host_id: node.id, probe:, interval: 0, **common, **opts)
    end

    it "boots the installer, switches back to the disk once it's up, and waits for the key login" do
      ssh.reachable = [false, true]
      op = install.call!

      expect(Pcs::Host.find(node.id).status).to eq("provisioned")
      expect(menu_defaults.first).to eq("install")
      expect(menu_file("aabbcc000001").read).to include("--default local")
      expect(Pcs::Host.find(node.id).pxe_install).to be(false)
      expect(ssh.forgotten).to eq(1)
      expect(op.steps.map(&:description))
        .to include("set n1's boot menu to install", "wait for the installer to answer at 10.0.0.11",
                    "set n1's boot menu back to its disk", "wait for n1 to accept pcs's key at 10.0.0.11",
                    "mark n1 provisioned")
    end

    context "when the host is up at its address (it's being reinstalled)" do
      let(:pings) { [true, true, false, true] }

      it "waits for it to go down before waiting for the installer" do
        install.call!
        expect(out.string).to include("wait for 10.0.0.11 to go quiet (n1 rebooting)")
      end
    end

    it "never leaves the menu set to install when it fails" do
      settings.install.timeout = 0
      pings.replace([false])
      op = install.call

      expect(op.error).to be_a(Termino::Operation::TimeoutError)
      expect(menu_file("aabbcc000001").read).to include("--default local")
      expect(Pcs::Host.find(node.id)).to have_attributes(pxe_install: false, status: "configured")
    end

    it "sets the menu back to the disk when interrupted (Ctrl-C)" do
      pings.replace([false])
      allow(probe).to receive(:ping?).and_raise(Interrupt)
      expect { install.call }.to raise_error(Interrupt)
      expect(menu_file("aabbcc000001").read).to include("--default local")
    end

    it "sets the menu back to the disk after a server stopped mid-install" do
      node.update!(pxe_install: true)
      allow(Pcs::Operations::Reconcile).to receive(:new).and_return(Pcs::Operations::Reconcile.new(settings:, pcm:,
                                                                                                   download:))
      described_class.interrupted(host_id: node.id)
      expect(Pcs::Host.find(node.id).pxe_install).to be(false)
      expect(menu_file("aabbcc000001").read).to include("--default local")
    end

    it "needs a configured host" do
      node.update!(status: "discovered")
      expect(install.call.error.message).to eq("n1 is discovered; configure it first")
    end

    it "only lists what it would do in a dry run" do
      op = install(dry_run: true).call!
      expect(op.steps.map(&:status).uniq).to eq([:planned])
      expect(Pcs::Host.find(node.id)).to have_attributes(pxe_install: false, status: "configured")
      expect(menu_file("aabbcc000001")).not_to exist
    end
  end
end
