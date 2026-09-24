#!/bin/bash
# PIM Base Provisioning Script (Fedora)
# Sets up cloud-init and basic system configuration for VM images
set -e

echo "=== PIM Base Provisioning (Fedora) ==="

echo "Installing cloud-init and essential packages..."
dnf install -y \
    cloud-init \
    cloud-utils-growpart \
    qemu-guest-agent \
    curl \
    ca-certificates

echo "Enabling qemu-guest-agent..."
systemctl enable qemu-guest-agent || true
systemctl start qemu-guest-agent || true

# Fedora's cloud.cfg turns SSH password auth off; pim provisions and verifies over password SSH
echo "Configuring cloud-init..."
cat > /etc/cloud/cloud.cfg.d/90_pim.cfg <<'EOF'
datasource_list: [ NoCloud, ConfigDrive, OpenStack, Ec2, GCE, Azure, None ]
ssh_pwauth: true
EOF

echo "Configuring SSH..."
cat > /etc/ssh/sshd_config.d/10-pim.conf <<'EOF'
PasswordAuthentication yes
EOF
systemctl enable sshd

echo "Cleaning up..."
dnf clean all

echo "=== Base provisioning complete ==="
