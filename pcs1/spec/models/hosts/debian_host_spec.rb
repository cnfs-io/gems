# frozen_string_literal: true

RSpec.describe Pcs1::DebianHost do
  before do
    TestProject.seed_all(test_dir,
      host: { "hostname" => "web1", "type" => "debian", "role" => "compute",
              "arch" => "amd64", "status" => "discovered", "pxe_boot" => true })
  end

  let(:host) { Pcs1::Host.first }

  describe "state machine override" do
    it "allows discovered → configured (skips keyed)" do
      allow(host).to receive(:configuration_complete?).and_return(true)
      expect(Pcs1::Dnsmasq).to receive(:reconcile!)
      expect(Pcs1::Netboot).to receive(:reconcile!)
      expect(host.fire_status_event(:configure)).to be_truthy
      expect(host.status).to eq("configured")
    end

    it "also allows keyed → configured" do
      host.status = "keyed"
      allow(host).to receive(:configuration_complete?).and_return(true)
      expect(Pcs1::Dnsmasq).to receive(:reconcile!)
      expect(Pcs1::Netboot).to receive(:reconcile!)
      expect(host.fire_status_event(:configure)).to be_truthy
      expect(host.status).to eq("configured")
    end

    it "blocks configure when configuration_complete? is false" do
      allow(host).to receive(:configuration_complete?).and_return(false)
      expect(host.fire_status_event(:configure)).to be_falsey
      expect(host.status).to eq("discovered")
    end
  end

  describe "#key!" do
    it "is a no-op for PXE targets in discovered state" do
      expect(Net::SSH).not_to receive(:start)
      host.key!
    end

    it "delegates to super for non-PXE hosts" do
      host.pxe_boot = false
      host.status = "discovered"
      host.connect_as = "admin"
      host.connect_password = "pass"

      # Will try SSH — just verify it attempts connection
      mock_ssh = instance_double("Net::SSH::Connection::Session")
      allow(mock_ssh).to receive(:exec!).and_return("")
      allow(Net::SSH).to receive(:start).and_yield(mock_ssh)

      # Need an SSH key file
      key_file = File.join(test_dir, "test_key.pub")
      File.write(key_file, "ssh-ed25519 AAAAC3 test@test")
      site = Pcs1::Site.first
      site.ssh_key = key_file
      site.save!

      host.key!
      expect(Net::SSH).to have_received(:start)
    end
  end

  describe "#boot_menu_entry" do
    it "returns a hash with install key, label, and paths" do
      entry = host.boot_menu_entry
      expect(entry).to be_a(Hash)
      expect(entry[:key]).to eq("install")
      expect(entry[:label]).to include("Debian")
      expect(entry[:kernel_path]).to include("amd64")
      expect(entry[:initrd_path]).to include("amd64")
    end

    it "uses the host arch for paths" do
      TestProject.seed_host(test_dir, "hostname" => "arm-host", "type" => "debian",
                                       "arch" => "arm64", "status" => "discovered")
      Pcs1::Host.reload!
      arm_host = Pcs1::Host.all.detect { |h| h.hostname == "arm-host" }
      entry = arm_host.boot_menu_entry
      expect(entry[:kernel_path]).to include("arm64")
    end
  end

  describe "#kernel_params" do
    it "interpolates hostname and domain" do
      params = host.kernel_params(base_url: "http://172.31.1.10:8080")
      expect(params).to include("hostname=web1")
      expect(params).to include("domain=test.local")
      expect(params).to include("preseed/url=http://172.31.1.10:8080/test.local/web1.preseed.cfg")
    end
  end

  describe "#generate_install_files" do
    it "generates preseed and post-install files" do
      allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["172.31.1.20"])

      output_dir = Pathname.new(test_dir) / "output"
      FileUtils.mkdir_p(output_dir)

      allow(Pcs1::Platform).to receive(:sudo_write) do |path, content|
        File.write(path, content)
      end

      host.generate_install_files(output_dir)

      preseed = output_dir / "web1.preseed.cfg"
      post_install = output_dir / "web1.install.sh"
      expect(preseed).to exist
      expect(post_install).to exist
      expect(preseed.read).to include("web1")
    end
  end
end
