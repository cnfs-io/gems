#!/bin/bash
# PIM Base Provisioning Script
# Sets up cloud-init and basic system configuration for VM images
set -e

echo "=== PIM Base Provisioning ==="

# Update package lists
echo "Updating package lists..."
apt-get update

# Install cloud-init and essential packages
echo "Installing cloud-init and essential packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    cloud-init \
    cloud-utils \
    cloud-guest-utils \
    qemu-guest-agent \
    acpid \
    curl \
    ca-certificates \
    gnupg \
    lsb-release

# Enable and start qemu-guest-agent
echo "Enabling qemu-guest-agent..."
systemctl enable qemu-guest-agent || true
systemctl start qemu-guest-agent || true

# Enable acpid for graceful shutdown
echo "Enabling acpid..."
systemctl enable acpid || true
systemctl start acpid || true

# Configure cloud-init datasources
echo "Configuring cloud-init datasources..."
cat > /etc/cloud/cloud.cfg.d/90_dpkg.cfg <<'EOF'
datasource_list: [ NoCloud, ConfigDrive, OpenStack, Ec2, GCE, Azure, None ]
EOF

# Configure SSH for cloud environments
echo "Configuring SSH..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Enable SSH on boot
systemctl enable ssh || systemctl enable sshd || true

# Clean up APT cache
echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Base provisioning complete ==="
