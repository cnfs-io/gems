---
---

# Plan 04 — Build Model Defaults

## Objective

Move `ssh_user` and `ssh_timeout` from `Pim::Config` to the `Pim::Build` model as attributes with sensible defaults. Update `LocalBuilder` to read all build-related values from the Build instance. Remove `ssh_user` and `ssh_timeout` from `Pim::Config`.

## Context — Read Before Starting

- `~/.local/share/ppm/gems/pim/lib/pim/models/build.rb` — Build model (already has memory, cpus, disk_size)
- `~/.local/share/ppm/gems/pim/lib/pim/config.rb` — Config (still has ssh_user, ssh_timeout after Plan 02)
- `~/.local/share/ppm/gems/pim/lib/pim/build/local_builder.rb` — reads ssh_user/ssh_timeout from Pim.config (after Plan 02)
- `~/.local/share/ppm/gems/pim/lib/pim/build/manager.rb` — build orchestration

## Implementation

### 1. Add ssh attributes to Build model — `lib/pim/models/build.rb`

Add attributes with default overrides:

```ruby
attribute :ssh_user, :string
attribute :ssh_timeout, :integer

def ssh_user
  super || "ansible"
end

def ssh_timeout
  super || 1800
end
```

Also add defaults for the existing attributes that currently fall back to Pim.config:

```ruby
def disk_size
  super || "20G"
end

def memory
  super || 2048
end

def cpus
  super || 2
end
```

These defaults were previously on `Pim::Config`. Now they live on the model itself. A build YAML file can override any of them:

```yaml
# data/builds/my-build.yml
profile: developer
iso: debian-12-arm64
disk_size: "40G"
memory: 4096
ssh_user: provision
```

### 2. Update LocalBuilder — `lib/pim/build/local_builder.rb`

After Plan 02, LocalBuilder accepts `build:` and reads most values from it. This plan removes the remaining `Pim.config.ssh_user` and `Pim.config.ssh_timeout` references:

- `@config.ssh_user` → `@build.ssh_user`
- `@config.ssh_timeout` → `@build.ssh_timeout`

For `image_dir`, continue reading from `Pim.config.image_dir` (that's legitimate global config — where images are stored on the local machine).

After this plan, LocalBuilder's relationship to config:
- `Pim.config.image_dir` — only global config reference
- `@build.*` — everything else (memory, cpus, disk_size, ssh_user, ssh_timeout, arch, profile, etc.)

### 3. Remove ssh_* from Pim::Config — `lib/pim/config.rb`

Remove `attr_accessor :ssh_user, :ssh_timeout` and their defaults from `initialize`.

### 4. Update VentoyConfig if needed — `lib/pim/services/ventoy_config.rb`

Check if VentoyConfig references any of the removed Config attributes. It shouldn't (it delegates to `Pim.config.ventoy`), but verify.

### 5. Update Manager — `lib/pim/build/manager.rb`

Ensure the Build instance is passed through to LocalBuilder with all attributes resolved. The manager should not be constructing a separate config object.

## Test Spec

### Build model specs

```ruby
describe Pim::Build do
  describe "defaults" do
    let(:build) { Pim::Build.new(id: "test", profile: "default", iso: "debian-12") }

    it "defaults memory to 2048" do
      expect(build.memory).to eq(2048)
    end

    it "defaults cpus to 2" do
      expect(build.cpus).to eq(2)
    end

    it "defaults disk_size to 20G" do
      expect(build.disk_size).to eq("20G")
    end

    it "defaults ssh_user to ansible" do
      expect(build.ssh_user).to eq("ansible")
    end

    it "defaults ssh_timeout to 1800" do
      expect(build.ssh_timeout).to eq(1800)
    end

    it "allows overriding memory" do
      build = Pim::Build.new(id: "test", profile: "default", iso: "debian-12", memory: 4096)
      expect(build.memory).to eq(4096)
    end

    it "allows overriding ssh_user" do
      build = Pim::Build.new(id: "test", profile: "default", iso: "debian-12", ssh_user: "root")
      expect(build.ssh_user).to eq("root")
    end
  end
end
```

### Config specs

```ruby
describe Pim::Config do
  it "does not respond to ssh_user" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:ssh_user)
  end

  it "does not respond to ssh_timeout" do
    config = Pim::Config.new
    expect(config).not_to respond_to(:ssh_timeout)
  end
end
```

## Verification

1. `bundle exec rspec` — all green
2. Grep: no `ssh_user` or `ssh_timeout` in `lib/pim/config.rb`
3. Grep: no `Pim.config.ssh_user` or `Pim.config.ssh_timeout` anywhere in lib/
4. Grep: no `Pim.config.memory`, `Pim.config.cpus`, `Pim.config.disk_size` anywhere in lib/
5. `Pim::Config` responds only to: `iso_dir`, `image_dir`, `serve_port`, `serve_profile`, `ventoy`, `flat_record`
