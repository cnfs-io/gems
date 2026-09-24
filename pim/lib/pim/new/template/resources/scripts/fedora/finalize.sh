#!/bin/bash
# PIM Finalize Script (Fedora)
# Prepares the image for capture by cleaning up and resetting state
set -e

echo "=== PIM Image Finalization (Fedora) ==="

echo "Cleaning cloud-init state..."
if command -v cloud-init &> /dev/null; then
    cloud-init clean --logs --seed || true
fi

# Regenerated on first boot by sshd-keygen
echo "Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

echo "Truncating machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

echo "Cleaning DNF cache..."
dnf clean all
dnf autoremove -y || true

echo "Clearing logs..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete
truncate -s 0 /var/log/wtmp || true
truncate -s 0 /var/log/lastlog || true

echo "Clearing bash history..."
for user_home in /root /home/*; do
    if [ -d "$user_home" ]; then
        rm -f "$user_home/.bash_history"
        rm -f "$user_home/.lesshst"
        rm -f "$user_home/.viminfo"
    fi
done

echo "Clearing temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

echo "Creating PIM verification marker..."
touch /root/.pim-verified

echo "Syncing filesystem..."
sync

echo "=== Finalization complete ==="
echo "Image is ready for capture."
