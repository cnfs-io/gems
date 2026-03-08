# frozen_string_literal: true

RSpec.describe Pcs::Host, :uses_fixture_project do
  describe ".load" do
    it "loads hosts from sites/sg/hosts.yml" do
      hosts = Pcs::Host.load("sg")
      expect(hosts).not_to be_empty
    end

    it "returns empty relation for site with no hosts" do
      hosts = Pcs::Host.where(site_id: "nonexistent")
      expect(hosts.to_a).to eq([])
    end
  end

  describe ".where" do
    it "returns all hosts for a site" do
      hosts = Pcs::Host.where(site_id: "sg")
      expect(hosts.count).to eq(8)
    end
  end

  describe ".find" do
    it "returns host by id" do
      host = Pcs::Host.find("6")
      expect(host.hostname).to eq("n1c1")
      expect(host.type).to eq("proxmox")
    end

    it "raises RecordNotFound for unknown id" do
      expect { Pcs::Host.find("999") }.to raise_error(FlatRecord::RecordNotFound)
    end
  end

  describe "STI resolution" do
    it "returns PveHost for type proxmox" do
      host = Pcs::Host.find("6")
      expect(host).to be_a(Pcs::PveHost)
    end

    it "returns RpiHost for type rpi" do
      host = Pcs::Host.find("8")
      expect(host).to be_a(Pcs::RpiHost)
    end
  end

  describe "site association" do
    it "host.site returns the site from hierarchy" do
      host = Pcs::Host.find("6")
      expect(host.site).to be_a(Pcs::Site)
      expect(host.site.name).to eq("sg")
    end

    it "host.fqdn uses site domain" do
      host = Pcs::Host.find("6")
      expect(host.fqdn).to eq("n1c1.sg.me.internal")
    end

    it "host.compute_network delegates to site" do
      host = Pcs::Host.find("6")
      expect(host.compute_network.subnet).to eq("172.31.1.0/24")
    end
  end

  describe "interface association" do
    it "has many interfaces" do
      host = Pcs::Host.find("6")
      expect(host.interfaces.size).to eq(2)
    end

    it "finds primary interface (on primary network)" do
      host = Pcs::Host.find("6")
      pi = host.primary_interface
      expect(pi).to be_a(Pcs::Interface)
      expect(pi.network.primary).to eq(true)
    end

    it "finds interface on a named network" do
      host = Pcs::Host.find("6")
      iface = host.interface_on("compute")
      expect(iface.ip).to eq("172.31.1.41")
    end

    it "returns nil for interface on unknown network" do
      host = Pcs::Host.find("6")
      expect(host.interface_on("unknown")).to be_nil
    end

    it "gets ip on a network" do
      host = Pcs::Host.find("6")
      expect(host.ip_on("storage")).to eq("172.31.2.41")
    end
  end

  describe ".find_by_mac" do
    it "matches case-insensitively" do
      host = Pcs::Host.find_by_mac("70:70:FC:05:2D:69", site_name: "sg")
      expect(host.id).to eq("6")
    end

    it "returns nil for unknown mac" do
      expect(Pcs::Host.find_by_mac("00:00:00:00:00:00", site_name: "sg")).to be_nil
    end
  end

  describe ".find_by_ip" do
    it "returns matching host" do
      host = Pcs::Host.find_by_ip("172.31.1.112", site_name: "sg")
      expect(host.id).to eq("6")
    end
  end

  describe "#update" do
    it "changes a field and persists" do
      host = Pcs::Host.find("6")
      host.update(hostname: "new-name")

      Pcs::Host.reload!
      reloaded = Pcs::Host.find("6")
      expect(reloaded.hostname).to eq("new-name")
    end
  end

  describe ".hosts_of_type" do
    it "returns hosts with matching type" do
      proxmox = Pcs::Host.hosts_of_type("proxmox", site_name: "sg")
      expect(proxmox.count).to eq(1)
      expect(proxmox.first.hostname).to eq("n1c1")
    end

    it "returns empty relation for unknown type" do
      expect(Pcs::Host.hosts_of_type("vmware", site_name: "sg").to_a).to eq([])
    end
  end

  describe ".merge_scan" do
    it "adds new host for unknown MAC/IP" do
      counts = Pcs::Host.merge_scan("sg", [{ ip: "172.31.1.200", mac: "aa:bb:cc:dd:ee:ff" }])
      expect(counts[:new]).to eq(1)

      Pcs::Host.reload!
      sg_hosts = Pcs::Host.where(site_id: "sg")
      expect(sg_hosts.count).to eq(9)

      new_host = sg_hosts.detect { |h| h.mac == "aa:bb:cc:dd:ee:ff" }
      expect(new_host.status).to eq("discovered")
    end

    it "updates discovered_ip when known MAC has new IP" do
      counts = Pcs::Host.merge_scan("sg", [{ ip: "172.31.1.200", mac: "70:70:fc:05:2d:69" }])
      expect(counts[:updated]).to eq(1)

      Pcs::Host.reload!
      host = Pcs::Host.find("6")
      expect(host.discovered_ip).to eq("172.31.1.200")
    end

    it "marks unchanged when known MAC has same IP" do
      counts = Pcs::Host.merge_scan("sg", [{ ip: "172.31.1.112", mac: "70:70:fc:05:2d:69" }])
      expect(counts[:unchanged]).to eq(1)
    end

    it "returns correct composite counts" do
      counts = Pcs::Host.merge_scan("sg", [
        { ip: "172.31.1.112", mac: "70:70:fc:05:2d:69" },  # unchanged
        { ip: "172.31.1.200", mac: "7a:45:58:c7:d4:4d" },  # updated (new IP)
        { ip: "172.31.1.250", mac: "ff:ff:ff:ff:ff:ff" }    # new
      ])
      expect(counts).to eq({ new: 1, updated: 1, unchanged: 1 })
    end
  end

  describe "PveHost class defaults" do
    it "reads default_preseed_interface from config" do
      expect(Pcs.config.service.proxmox.default_preseed_interface).to eq("enp1s0")
    end

    it "reads default_preseed_device from config" do
      expect(Pcs.config.service.proxmox.default_preseed_device).to eq("/dev/sda")
    end

    it "allows overriding defaults via config" do
      original = Pcs.config.service.proxmox.default_preseed_interface
      Pcs.config.service.proxmox.default_preseed_interface = "eno1"
      expect(Pcs.config.service.proxmox.default_preseed_interface).to eq("eno1")
    ensure
      Pcs.config.service.proxmox.default_preseed_interface = original
    end

    it "populates instance from class default on initialize" do
      host = Pcs::PveHost.new
      expect(host.preseed_interface).to eq("enp1s0")
      expect(host.preseed_device).to eq("/dev/sda")
    end

    it "does not override existing instance values" do
      host = Pcs::PveHost.new(preseed_interface: "eno2", preseed_device: "/dev/nvme0n1")
      expect(host.preseed_interface).to eq("eno2")
      expect(host.preseed_device).to eq("/dev/nvme0n1")
    end

    it "applies class defaults to STI-loaded records" do
      host = Pcs::Host.find("6")
      expect(host).to be_a(Pcs::PveHost)
      expect(host.preseed_interface).to be_a(String)
      expect(host.preseed_device).to be_a(String)
    end
  end

  describe "persistence" do
    it "round-trips through save" do
      host = Pcs::Host.find("6")
      host.update(hostname: "saved-host")

      Pcs::Host.reload!
      reloaded = Pcs::Host.find("6")
      expect(reloaded.hostname).to eq("saved-host")
    end
  end
end
