# frozen_string_literal: true

RSpec.describe Pcs1::Netboot do
  before do
    TestProject.seed_all(test_dir,
      host: { "hostname" => "ops1", "type" => "debian", "role" => "control",
              "arch" => "amd64", "status" => "configured", "pxe_boot" => false })
    allow(Pcs1::Platform.current).to receive(:local_ips).and_return(["172.31.1.20"])
  end

  describe ".menus_dir" do
    it "returns a Pathname under the data dir" do
      dir = Pcs1::Netboot.menus_dir
      expect(dir).to be_a(Pathname)
      expect(dir.to_s).to include("menus")
    end
  end

  describe ".assets_dir" do
    it "returns a Pathname under the data dir" do
      dir = Pcs1::Netboot.assets_dir
      expect(dir).to be_a(Pathname)
      expect(dir.to_s).to include("assets")
    end
  end

  describe ".reconcile!" do
    it "calls generate_all" do
      expect(Pcs1::Netboot).to receive(:generate_all)
      Pcs1::Netboot.reconcile!
    end
  end

  describe ".status" do
    it "returns stopped when container does not exist" do
      allow(Pcs1::Platform).to receive(:capture).and_return("")
      expect(Pcs1::Netboot.status).to eq("stopped")
    end
  end
end
