#!/usr/bin/env bash
# Draft additions to the pdt-ppm pcs package's install.sh (see README.md).

post_install() {
  local volumes="${PCM_VOLUMES_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pcm/volumes}"

  # Where pcs writes, and the netboot and dnsmasq containers read
  mkdir -p "$volumes/dnsmasq/dnsmasq.d" "$volumes/netboot/config/menus" "$volumes/netboot/assets"

  # Rootless podman may bind DHCP (67, 4011) and TFTP (69) on the host network
  if [[ "$(uname -s)" == "Linux" ]]; then
    echo "net.ipv4.ip_unprivileged_port_start=67" | sudo tee /etc/sysctl.d/60-pcs-netboot.conf >/dev/null
    sudo sysctl -q --load /etc/sysctl.d/60-pcs-netboot.conf
    # The containerised dnsmasq replaces the system one (both need port 67)
    if systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
      sudo systemctl disable --now dnsmasq
    fi
  fi
}
