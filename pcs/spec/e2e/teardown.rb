#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone teardown — safe to run anytime
require_relative "support/e2e_root"
require_relative "support/test_bridge"
require_relative "support/qemu_launcher"

# Kill any running QEMU instances from e2e
`pgrep -f pcs-e2e`.split("\n").each do |pid|
  Process.kill("TERM", pid.to_i) rescue nil
end

# Kill any leftover dnsmasq on the test bridge
`pgrep -f "pcs-test0"`.split("\n").each do |pid|
  system("sudo kill #{pid} 2>/dev/null")
end

# Clean up NAT rules (safe to run even if they don't exist)
uplink = `ip route show default 2>/dev/null`[/dev\s+(\S+)/, 1]
if uplink
  system("sudo iptables -t nat -D POSTROUTING -s 10.99.0.0/24 -o #{uplink} -j MASQUERADE 2>/dev/null")
  system("sudo iptables -D FORWARD -i #{Pcs::E2E::TestBridge::BRIDGE_NAME} -o #{uplink} -j ACCEPT 2>/dev/null")
  system("sudo iptables -D FORWARD -i #{uplink} -o #{Pcs::E2E::TestBridge::BRIDGE_NAME} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null")
end

# Kill any leftover HTTP servers for e2e
`pgrep -f "httpd.*8080"`.split("\n").each do |pid|
  Process.kill("TERM", pid.to_i) rescue nil
end

Pcs::E2E::TestBridge.new.down
Pcs::E2E.cleanup!

puts "Teardown complete."
