# Drafts for the pdt-ppm `pcs` package

These files belong in the pdt-ppm repo (`git@github.com:maxcole/pdt-ppm`, `packages/pcs`).
They're drafted here because that repo's working copy wasn't settled. The layout mirrors the
package, so moving them is a copy:

```
cp -R ppm/home/.config <pdt-ppm>/packages/pcs/home/
# merge ppm/install.sh's post_install into <pdt-ppm>/packages/pcs/install.sh
```

## What's here

| File | What it is |
|---|---|
| `home/.config/pcm/containers/dnsmasq/compose.yml` | Proxy DHCP for PXE (`dockurr/dnsmasq:2.93`), config from `${PCM_VOLUMES_HOME}/dnsmasq/dnsmasq.d` (read-only) |
| `home/.config/pcm/containers/netboot/compose.yml` | netboot.xyz (`netbootxyz/netbootxyz:0.7.6-nbxyz24`): TFTP plus HTTP on `NETBOOT_HTTP_PORT` (8080), mounting `${PCM_VOLUMES_HOME}/netboot/{config,assets}` |
| `*/.env.schema` | Every variable, with defaults (image, tag, ports) |
| `install.sh` | A `post_install` to merge: creates the volume directories, lowers `ip_unprivileged_port_start` to 67, disables a system dnsmasq |

Both pass `pcm validate`, checked with:

```
PCM_CONTAINERS_HOME=<dir with the two services> PCM_VOLUMES_HOME=<dir> pcm validate dnsmasq netboot
```

## Decisions made in these drafts

- **netboot.xyz serves TFTP; dnsmasq doesn't.** dnsmasq's `pxe-service` lines point clients at the
  control plane, where netboot.xyz's TFTP hands out its boot loaders and menus.
- **Host networking for both.** DHCP needs broadcasts, and TFTP replies from ephemeral ports
  (port mapping breaks it).
- **Rootless podman, with `net.ipv4.ip_unprivileged_port_start=67`** so the containers can bind
  67, 69 and 4011. The alternative is rootful podman, which pcm doesn't do.
- **dnsmasq runs with its own command line**, not the image's entrypoint: `--port=0` (no DNS, so it
  never fights systemd-resolved on 53), and config only from pcs's directory.

## Changes to make to the package itself

- **`package.yml`: remove `dnsmasq` from `system.debian`.** The container replaces it, and a
  system dnsmasq would hold port 67. (`install.sh` also disables one if it's already there.)
- **Consider dropping the qemu packages** from `system.debian` until the end-to-end test (step 7)
  needs them on the Pi.

## Still to verify on the Pi (step 7 covers it)

- Whether rootless podman with the sysctl is enough for dnsmasq's proxy DHCP. It may also need
  `CAP_NET_RAW` in the host's user namespace. If it isn't enough, the fallback is rootful podman
  for these two services.
- That netboot.xyz runs `MAC-<mac>.ipxe` from its menus directory before its own menu.
- That dnsmasq sends `netboot.xyz.efi` as-is: a basename containing a dot shouldn't get the
  `.0` layer suffix.
