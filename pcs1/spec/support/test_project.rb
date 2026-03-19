# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "yaml"

module TestProject
  def self.create(dir)
    FileUtils.mkdir_p(File.join(dir, "data"))
    File.write(File.join(dir, "pcs.rb"), "# test project marker\n")
    dir
  end

  def self.seed_site(dir, attrs = {})
    defaults = {
      "id" => "1",
      "name" => "test-site",
      "domain" => "test.local",
      "timezone" => "UTC",
      "ssh_key" => "~/.ssh/id_ed25519"
    }
    write_yaml(dir, "sites.yml", [defaults.merge(stringify_keys(attrs))])
  end

  def self.seed_network(dir, attrs = {})
    defaults = {
      "id" => "1",
      "name" => "compute",
      "subnet" => "172.31.1.0/24",
      "gateway" => "172.31.1.1",
      "primary" => true,
      "site_id" => "1"
    }
    write_yaml(dir, "networks.yml", [defaults.merge(stringify_keys(attrs))])
  end

  def self.seed_host(dir, attrs = {})
    defaults = {
      "id" => "1",
      "hostname" => "test-host",
      "role" => "compute",
      "type" => "debian",
      "arch" => "amd64",
      "status" => "discovered",
      "pxe_boot" => false,
      "site_id" => "1"
    }
    write_yaml(dir, "hosts.yml", [defaults.merge(stringify_keys(attrs))])
  end

  def self.seed_hosts(dir, hosts_array)
    write_yaml(dir, "hosts.yml", hosts_array.map { |h| stringify_keys(h) })
  end

  def self.seed_interface(dir, attrs = {})
    defaults = {
      "id" => "1",
      "mac" => "aa:bb:cc:dd:ee:ff",
      "discovered_ip" => "172.31.1.100",
      "configured_ip" => "172.31.1.20",
      "name" => "eth0",
      "host_id" => "1",
      "network_id" => "1"
    }
    write_yaml(dir, "interfaces.yml", [defaults.merge(stringify_keys(attrs))])
  end

  def self.seed_interfaces(dir, interfaces_array)
    write_yaml(dir, "interfaces.yml", interfaces_array.map { |i| stringify_keys(i) })
  end

  def self.seed_all(dir, site: {}, network: {}, host: {}, interface: {})
    seed_site(dir, site)
    seed_network(dir, network)
    seed_host(dir, host)
    seed_interface(dir, interface)
  end

  def self.write_yaml(dir, filename, data)
    File.write(File.join(dir, "data", filename), YAML.dump(data))
  end

  def self.stringify_keys(hash)
    hash.transform_keys(&:to_s)
  end
end
