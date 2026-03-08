#!/bin/bash
exec > /root/install.log 2>&1
set -ex

# Post-installation script (runs during preseed late_command)
echo "=== Post-installation script starting ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update || true

echo "=== Post-installation complete ==="
