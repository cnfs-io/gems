Pcs.configure do |config|
  config.networking do |net|
    net.dns_fallback_resolvers = ["1.1.1.1", "8.8.8.8"]
  end

  config.flat_record do |fr|
    fr.backend = :yaml
    fr.id_strategy = :integer
    fr.hierarchy model: :site, key: :name
  end

  config.service.dnsmasq do |dns|
    dns.proxy = true
  end

  config.service.netboot do |nb|
    nb.image = "docker.io/netbootxyz/netbootxyz"
    nb.ipxe_timeout = 10
    nb.netboot_dir = Pathname.new("/opt/pcs/netboot")
  end

  config.service.proxmox do |pve|
    pve.default_preseed_interface = "enp1s0"
    pve.default_preseed_device = "/dev/sda"
  end
end

Pcs::Site.top_level_domain = "me.internal"
