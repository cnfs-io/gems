#!/bin/bash
# PIM Finalize Script
# Prepares the image for capture by cleaning up and resetting state
set -e

echo "=== PIM Image Finalization ==="

# Clean cloud-init state
echo "Cleaning cloud-init state..."
if command -v cloud-init &> /dev/null; then
    cloud-init clean --logs --seed || true
fi

# Remove SSH host keys (will be regenerated on first boot)
echo "Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# Truncate machine-id (will be regenerated on first boot)
echo "Truncating machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Clean APT cache
echo "Cleaning APT cache..."
apt-get clean
apt-get autoremove -y || true
rm -rf /var/lib/apt/lists/*

# Clear logs
echo "Clearing logs..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
find /var/log -type f -name "*.1" -delete
truncate -s 0 /var/log/wtmp || true
truncate -s 0 /var/log/lastlog || true

# Clear bash history
echo "Clearing bash history..."
for user_home in /root /home/*; do
    if [ -d "$user_home" ]; then
        rm -f "$user_home/.bash_history"
        rm -f "$user_home/.lesshst"
        rm -f "$user_home/.viminfo"
    fi
done

# Clear tmp directories
echo "Clearing temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# PIM verification marker
echo "Creating PIM verification marker..."
touch /root/.pim-verified

# Sync filesystem
echo "Syncing filesystem..."
sync

echo "=== Finalization complete ==="
echo "Image is ready for capture."
