# frozen_string_literal: true

RSpec.describe Pcs1::Site do
  before do
    TestProject.seed_all(test_dir)
  end

  let(:site) { Pcs1::Site.first }

  describe "#ssh_public_key_content" do
    it "returns nil when ssh_key is nil" do
      site.ssh_key = nil
      expect(site.ssh_public_key_content).to be_nil
    end

    it "returns nil when ssh_key file does not exist" do
      site.ssh_key = "/tmp/nonexistent_key.pub"
      expect(site.ssh_public_key_content).to be_nil
    end

    it "returns file content when ssh_key file exists" do
      key_file = File.join(test_dir, "test_key.pub")
      File.write(key_file, "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA test@test\n")
      site.ssh_key = key_file
      expect(site.ssh_public_key_content).to eq("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA test@test")
    end
  end

  describe "#reconcile!" do
    it "delegates to Dnsmasq.reconcile! and Netboot.reconcile!" do
      expect(Pcs1::Dnsmasq).to receive(:reconcile!)
      expect(Pcs1::Netboot).to receive(:reconcile!)
      site.reconcile!
    end
  end
end
