# frozen_string_literal: true

module Pcs
  # What a host needs to PXE boot and install: its boot menu (a per-MAC iPXE
  # script netboot.xyz picks up before its own menu), the installer it boots,
  # and the preseed that answers the installer's questions.
  #
  # Each host's menu carries its own kernel parameters (address, hostname,
  # preseed URL), so hosts can't get each other's settings.
  class PxeTarget
    attr_reader :host, :interface, :network, :settings

    # Targets for every host pcs can install that's configured enough to.
    def self.all(settings: Pcs.settings)
      Host.all.select(&:pxe?).filter_map { |host| new(host, settings:) if host.missing_configuration.empty? }
    end

    def initialize(host, settings: Pcs.settings)
      @host = host
      @interface = host.primary_interface
      @network = interface.network
      @settings = settings
    end

    def mac_hex = interface.mac.delete(":")

    # netboot.xyz looks for this name in its menus directory (over TFTP).
    def menu_file = "MAC-#{mac_hex}.ipxe"

    def install? = host.pxe_install

    def codename = settings.install.debian_codename
    def arch = host.arch

    def server_ip = network.control_plane_ip
    def base_url = "http://#{server_ip}:#{settings.netboot.http_port}"

    # Installer files, relative to the netboot assets directory.
    def installer_dir = "debian-installer/#{codename}/#{arch}"
    def kernel_url = "#{base_url}/#{installer_dir}/linux"
    def initrd_url = "#{base_url}/#{installer_dir}/#{initrd_name}"

    # Debian's initrd, or (with firmware on) one with the firmware appended.
    def initrd_name = settings.install.firmware ? "initrd-firmware.gz" : "initrd.gz"

    def preseed_file = "pcs/#{host.hostname}.preseed.cfg"
    def post_install_file = "pcs/#{host.hostname}.post-install.sh"
    def preseed_url = "#{base_url}/#{preseed_file}"
    def post_install_url = "#{base_url}/#{post_install_file}"

    # The installer's kernel command line.
    def kernel_params
      install = settings.install
      { "auto" => "true", "priority" => "critical", "locale" => install.locale, "keymap" => install.keymap,
        **network_params, "hostname" => host.hostname, "domain" => host.site&.domain, "preseed/url" => preseed_url }
        .compact.map { |key, value| "#{key}=#{value}" }.join(" ")
    end

    # A static address from the start, so the installed system keeps it
    # without further setup.
    def network_params
      {
        "netcfg/choose_interface" => "auto", "netcfg/disable_autoconfig" => "true",
        "netcfg/get_ipaddress" => interface.configured_ip, "netcfg/get_netmask" => network.netmask,
        "netcfg/get_gateway" => network.gateway, "netcfg/get_nameservers" => network.nameservers.first,
        "netcfg/confirm_static" => "true"
      }
    end
  end
end
