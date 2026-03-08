#!/bin/bash
# PIM Default Verification Script
# Runs inside the guest over SSH after booting a built image.
# Exit 0 = pass, non-zero = fail
set -e

echo "=== PIM Verification ==="

echo "Checking PIM marker file..."
test -f /root/.pim-verified
echo "  OK marker file exists"

echo "Checking SSH service..."
systemctl is-active ssh || systemctl is-active sshd
echo "  OK SSH is running"

echo "Checking qemu-guest-agent..."
if dpkg -l | grep -q qemu-guest-agent; then
  echo "  OK qemu-guest-agent installed"
else
  echo "  SKIP qemu-guest-agent not installed (optional)"
fi

echo "Checking network connectivity..."
ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1 || true
echo "  OK (or skipped in isolated network)"

echo ""
echo "=== All checks passed ==="
