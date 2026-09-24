---
---

# Plan 03 — Netmask Calculation and Profile Hash Access

## Context — read these files first

- `lib/pcs/adapters/dnsmasq.rb` — `write_config` hardcodes `netmask = "255.255.255.0"` with "spike" comment
- `lib/pcs/models/profile.rb` — defines a `[]` method that contradicts the FlatRecord access convention
- `CLAUDE.md` — states "FlatRecord does not implement `[]` — hash access will raise NoMethodError"

## Overview

Two small but important fixes:

1. The Dnsmasq adapter hardcodes a /24 netmask. Real sites may use /22, /25, or other prefix lengths. The subnet CIDR is already available — calculate the netmask from it.

2. The Profile model defines a `[]` method that allows hash-style access, contradicting the project-wide convention that all FlatRecord models use method access only. This creates an inconsistency and could mask bugs.

## Implementation

### 1. Fix Dnsmasq netmask calculation

In `lib/pcs/adapters/dnsmasq.rb`, replace the hardcoded netmask:

**Before:**
```ruby
netmask = "255.255.255.0" # /24 assumption for spike
```

**After:**
```ruby
prefix_len = servers_subnet.split("/").last.to_i
netmask = prefix_to_netmask(prefix_len)
```

Add a private helper method:

```ruby
def self.prefix_to_netmask(prefix_len)
  mask = (0xFFFFFFFF << (32 - prefix_len)) & 0xFFFFFFFF
  [mask].pack("N").unpack("C4").join(".")
end
private_class_method :prefix_to_netmask
```

Also update the method signature to pass `prefix_len` through to the ERB template if the template uses the netmask variable. Check `lib/pcs/templates/dnsmasq/pcs-pxe-proxy.conf.erb` to see how netmask is used.

### 2. Remove `[]` from Profile

In `lib/pcs/models/profile.rb`, remove the `[]` method entirely:

```ruby
# REMOVE this:
def [](key)
  send(key.to_s) if respond_to?(key.to_s)
end
```

Then search for any callers that use hash-style access on Profile instances:

```
grep -rn "\bprofile\[" lib/ spec/
grep -rn "\.resolve\[" lib/ spec/
```

If any callers exist, convert them to method access (`.field_name` instead of `[:field_name]`).

The `resolve` method returns a Hash (from `resolved_attributes`), so `profile.resolve(:field)` is fine — that's calling a method, not hash-style access on the model. The `to_h` method also returns a Hash, which is fine for serialization.

Check templates too — any ERB templates that access profile data should use method calls, not hash access.

## Test Spec

### Dnsmasq netmask spec

Add a spec for the new helper. In `spec/pcs/adapters/dnsmasq_spec.rb` (create if needed):

```ruby
RSpec.describe Pcs::Adapters::Dnsmasq do
  describe ".prefix_to_netmask" do
    # Access private method for testing
    subject { described_class.send(:prefix_to_netmask, prefix) }

    context "with /24" do
      let(:prefix) { 24 }
      it { is_expected.to eq("255.255.255.0") }
    end

    context "with /22" do
      let(:prefix) { 22 }
      it { is_expected.to eq("255.255.252.0") }
    end

    context "with /25" do
      let(:prefix) { 25 }
      it { is_expected.to eq("255.255.255.128") }
    end

    context "with /16" do
      let(:prefix) { 16 }
      it { is_expected.to eq("255.255.0.0") }
    end
  end
end
```

### Profile spec

Add a regression spec in `spec/pcs/models/profile_spec.rb` confirming hash-style access is not available:

```ruby
it "does not support hash-style access" do
  profile = Pcs::Profile.all.first
  expect(profile).not_to respond_to(:[])
end
```

## Verification

- [ ] `grep -n "assumption\|spike\|hardcode" lib/pcs/adapters/dnsmasq.rb` returns zero matches
- [ ] `grep -n "def \[\]" lib/pcs/models/profile.rb` returns zero matches
- [ ] `bundle exec rspec` passes
- [ ] New dnsmasq adapter spec passes with multiple prefix lengths
