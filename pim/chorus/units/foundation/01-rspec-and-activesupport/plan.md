---
---

# Plan 01: RSpec and ActiveSupport

## Context

Read these files before starting:

- `lib/pim.rb` — main module, contains `Pim::DeepMerge`, `Pim::Config`, `Pim::Profile`, `Pim::Server`, `Pim::CLI`
- `lib/pim/config.rb` — `PimConfig::CLI` (Thor subcommand for config get/set)
- `lib/pim/profile.rb` — `PimProfile::Config`, `PimProfile::Manager`, `PimProfile::CLI`; contains its own `DeepMerge` copy
- `lib/pim/iso.rb` — `PimIso::Config`, `PimIso::CLI`
- `lib/pim/build.rb` — `PimBuild::Config`; contains a third `deep_merge` as a private method
- `pim.gemspec` — current dependencies

## Objective

Establish RSpec as the test framework, replace all custom DeepMerge implementations with ActiveSupport's `Hash#deep_merge`, and write unit specs for the core configuration classes.

## Implementation

### 1. Add dependencies

Add to `pim.gemspec`:

```ruby
spec.add_dependency "activesupport", ">= 7.0"

spec.add_development_dependency "rspec", "~> 3.0"
spec.add_development_dependency "rspec-mocks", "~> 3.0"
```

### 2. RSpec setup

Create `spec/spec_helper.rb`:

```ruby
require "pim"

RSpec.configure do |config|
  config.filter_run_excluding integration: true
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.order = :random
end
```

Create `.rspec`:

```
--require spec_helper
--format documentation
--color
```

### 3. Replace DeepMerge with ActiveSupport

There are **three** copies of deep merge to remove:

1. `lib/pim.rb` — `Pim::DeepMerge` module and its usage in `Pim::Config#load_runtime_config`
2. `lib/pim/profile.rb` — `PimProfile::DeepMerge` module and its usage in `PimProfile::Config`
3. `lib/pim/build.rb` — `PimBuild::Config#deep_merge` private method

Replace all with:

```ruby
require "active_support/core_ext/hash/deep_merge"
```

Then change all call sites from `DeepMerge.merge(a, b)` or `deep_merge(a, b)` to `a.deep_merge(b)`.

**Important:** The custom implementations treat `nil` overlay values as "keep the old value" (the `new_val.nil?` check in profile.rb and build.rb). ActiveSupport's `deep_merge` does not — it will set the key to `nil`. If this behavior is intentional, use the block form:

```ruby
a.deep_merge(b) { |_key, old_val, new_val| new_val.nil? ? old_val : new_val }
```

Verify whether any profiles or config files actually rely on `nil` values to mean "inherit from default." If they do, use the block form. If they don't (likely), the plain `deep_merge` is sufficient.

### 4. Add ActiveSupport require to pim.rb

At the top of `lib/pim.rb`, add:

```ruby
require "active_support/core_ext/hash/deep_merge"
```

Remove the `Pim::DeepMerge` module entirely. Remove `PimProfile::DeepMerge` module. Remove `PimBuild::Config#deep_merge` private method.

## Test spec

### `spec/pim/config_spec.rb`

Test `Pim::Config`:

- Loads global config from a YAML file
- Loads project config from `$PWD/pim.yml`
- Deep merges project over global (project values win)
- Returns empty hash when no config files exist
- Handles malformed YAML gracefully (warns, returns empty)
- Exposes `serve_defaults` from runtime config
- Delegates to `PimProfile::Config` for profile access
- Delegates to `PimIso::Config` for ISO access

Use `tmp` directories with known YAML fixtures. Set `project_dir:` explicitly rather than relying on `Dir.pwd`.

### `spec/pim/profile_spec.rb`

Test `PimProfile::Config`:

- Loads profiles from `profiles.d/*.yml` files
- Merges named profile over `default` profile
- Returns default profile when asked for `default`
- Returns empty hash for unknown profile name (merged over default)
- Lists profile names sorted alphabetically
- Handles missing `profiles.d/` directory

Test `Pim::Profile`:

- Exposes `name`, `data`, `to_h`, `[]`
- Finds preseed template by profile name with fallback to default
- Finds install template by profile name with fallback to default
- Checks project directory before global directory for templates
- Returns `nil` when no template exists

### `spec/pim/iso_spec.rb`

Test `PimIso::Config` (read `lib/pim/iso.rb` first to understand the interface):

- Loads ISO definitions from `isos.d/*.yml` files
- Resolves ISO by key
- Lists available ISOs
- Handles missing `isos.d/` directory

### `spec/pim/build/config_spec.rb`

Test `PimBuild::Config`:

- Applies default build config values
- Merges runtime config `build` section over defaults
- Resolves `image_dir` with environment variable expansion
- Returns correct `ssh_user`, `ssh_timeout`, `ssh_port`
- Returns builder type for architecture

## Verification

```bash
# All unit specs pass
bundle exec rspec

# No references to custom DeepMerge remain
grep -r "DeepMerge" lib/    # should return nothing
grep -r "def deep_merge" lib/  # should return nothing

# ActiveSupport is used
grep -r "deep_merge" lib/    # should show hash.deep_merge calls
```
