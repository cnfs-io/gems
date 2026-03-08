---
---

# Plan 03 — Builder Paths

## Context

Read before starting:
- `lib/pim/models/profile.rb` — `preseed_template`, `install_template`, `verification_script` methods
- `lib/pim/services/script_loader.rb` — `SCRIPTS_DIR` constant, script resolution
- `lib/pim.rb` — `Pim::Server` class, template/script serving
- `lib/pim/build/local_builder.rb` — build pipeline (uses Server, ScriptLoader)
- `lib/pim/services/verifier.rb` — verification script resolution
- `docs/layout-refactor/README.md` — target layout

## Goal

Update all path references that resolve builder components (preseeds, post_installs, scripts, verifications) to use `builders/` instead of the old `.d` directories.

## Path Mapping

| Old path | New path |
|----------|----------|
| `preseeds.d/<name>.cfg.erb` | `builders/preseeds/<name>.cfg.erb` |
| `installs.d/<name>.sh` | `builders/post_installs/<name>.sh` |
| `scripts.d/<name>.sh` | `builders/scripts/<name>.sh` |
| `verifications.d/<name>.sh` | `builders/verifications/<name>.sh` |

## Implementation

### 1. Update `Pim::Profile` template methods (`lib/pim/models/profile.rb`)

Change `find_template` and the methods that call it:

```ruby
def preseed_template(name = nil)
  name ||= id
  find_template('builders/preseeds', "#{name}.cfg.erb") ||
    (name != 'default' && find_template('builders/preseeds', 'default.cfg.erb'))
end

def install_template(name = nil)
  name ||= id
  find_template('builders/post_installs', "#{name}.sh") ||
    (name != 'default' && find_template('builders/post_installs', 'default.sh'))
end

def verification_script(name = nil)
  name ||= id
  find_template('builders/verifications', "#{name}.sh") ||
    (name != 'default' && find_template('builders/verifications', 'default.sh'))
end
```

The `find_template` private method stays unchanged — it already takes a subdir parameter.

### 2. Update `Pim::ScriptLoader` (`lib/pim/services/script_loader.rb`)

Change the constant:

```ruby
SCRIPTS_DIR = 'builders/scripts'
```

No other changes needed — `find_file` already uses `SCRIPTS_DIR` as the subdir.

### 3. Update `Pim::Verifier` error message (`lib/pim/services/verifier.rb`)

The error message references the old path. Update:

```ruby
def find_verification_script
  script = @profile.verification_script
  unless script
    raise VerifyError, "No verification script for profile '#{@profile.id}'. " \
                       "Create builders/verifications/#{@profile.id}.sh or builders/verifications/default.sh"
  end
  script
end
```

### 4. Verify `Pim::Server` — no changes needed

The Server class receives preseed and install content via `@profile.preseed_template(name)` and `@profile.install_template(name)` — it doesn't hardcode paths. Since those Profile methods are updated in step 1, the Server works automatically.

### 5. Verify `Pim::LocalBuilder` — no changes needed

LocalBuilder creates a `Pim::Server` instance and a `Pim::ScriptLoader` instance. Both are updated in steps 1-2. The builder itself doesn't hardcode any template/script paths.

## Test Spec

### Update `spec/pim/models/profile_spec.rb`

Any tests that set up template files in `preseeds.d/`, `installs.d/`, `verifications.d/` must use new paths:

- `preseeds.d/default.cfg.erb` → `builders/preseeds/default.cfg.erb`
- `installs.d/default.sh` → `builders/post_installs/default.sh`
- `verifications.d/default.sh` → `builders/verifications/default.sh`

### Update `spec/pim/verifier_spec.rb`

Update any fixture paths and error message expectations:
- Error message now references `builders/verifications/` not `verifications.d/`

### Add/update ScriptLoader specs

If script_loader specs exist, update fixture paths from `scripts.d/` to `builders/scripts/`.

### Integration with project scaffold

The full integration test from plan-01 (un-pended in plan-02) should now exercise the complete path:
1. `pim new` creates scaffold with `builders/` layout
2. FlatRecord loads from `data/`
3. Profile template resolution finds files in `builders/`

## Verification

```bash
bundle exec rspec
# All specs pass

# Manual: full smoke test
pim new /tmp/testproject
cd /tmp/testproject
pim profile list
pim profile show default
pim serve default          # should serve preseed from builders/preseeds/
# Ctrl+C
```
