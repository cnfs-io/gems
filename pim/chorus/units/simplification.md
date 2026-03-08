---
objective: "Simplify PIM's initialization, configuration, and data layout."
status: complete
---

# Simplification Tier — PIM

## Objective

Simplify PIM's initialization, configuration, and data layout. Remove legacy XDG/.d-directory patterns, clean up `Pim::Config` to contain only true global config, make the `pim.rb` config block the single initialization point for all dependencies (FlatRecord, RestCli), and establish conventions for project-based shared data.

**The question this tier answers:** Can PIM boot cleanly from a single `pim.rb` config block with no separate initialization steps, a slim global config, and explicit per-model data path control?

## Background

PIM evolved from a user-scoped tool (`~/.config/pim` with `.d` directories) to a fully project-scoped tool. Several artifacts of the old design remain:

1. **`configure_flat_record!`** — a separate method called after `pim.rb` is loaded, configuring FlatRecord with XDG paths. This should be folded into the `Pim.configure` block.
2. **`Pim::Config` bloat** — contains build-level attributes (`memory`, `cpus`, `disk_size`, `ssh_user`, `ssh_timeout`) that belong on the Build model, not global config.
3. **`Pim.root` returns String** — should return Pathname like `Rails.root`.
4. **FlatRecord stores paths as strings internally** — should use Pathname throughout.
5. **`BuildConfig` service** — exists solely to delegate between `Pim.config` and per-build overrides. Once build-level attrs move to the Build model, this class becomes unnecessary.
6. **Hardcoded shared profile path** — `Profile::SHARED_PROFILES_DIR` points at an XDG location. Users should control per-model data paths explicitly in `pim.rb`.

## Design Decisions

### Config block as single initialization point

`pim.rb` is the only configuration file. The `Pim.configure` block configures PIM itself and, via nested blocks, configures FlatRecord and RestCli. No separate `configure_flat_record!` call.

```ruby
Pim.configure do |config|
  config.flat_record do |fr|
    fr.backend = :yaml
    fr.id_strategy = :string
  end
end

# Optional: per-model data path overrides
Pim::Profile.data_paths = [Pim.root.join("../share/profiles")]
```

### Build-level attributes on the Build model

`memory`, `cpus`, `disk_size` are per-build attributes declared on `Pim::Build`. `ssh_user` and `ssh_timeout` are also per-build (SSH is used during the build process to provision the VM, not for target deployment). The Build model provides defaults for these attributes.

### Pim.root returns Pathname

Consistent with Rails convention. All internal path operations use Pathname.

### FlatRecord Pathname internals

`data_paths` stored as Pathname array internally. Setter coerces strings to Pathnames. Consumers call `.to_s` only at IO boundaries.

### Per-model data_paths is user-controlled

No hardcoded shared paths. If a user wants to share profiles between PIM and PCS, they set `Pim::Profile.data_paths` in `pim.rb`. The `pim new` template does not include this by default — it's opt-in.

### BuildConfig removed

`LocalBuilder` reads build attributes directly from the Build model instance. `image_dir` comes from `Pim.config`. No intermediary needed.

## Plans

| # | Name | Description |
|---|------|-------------|
| 01 | flat-record-pathname | Convert FlatRecord data_paths to Pathname internally |
| 02 | config-cleanup | Remove build-level attrs from Pim::Config, add nested F/R config block, remove BuildConfig |
| 03 | boot-simplification | Eliminate configure_flat_record!, Pim.root returns Pathname, update boot sequence |
| 04 | build-model-defaults | Move memory/cpus/disk_size/ssh_user/ssh_timeout to Build model with defaults |
| 05 | template-and-profile-cleanup | Update pim new template, remove SHARED_PROFILES_DIR constant, update specs |

## Completion Criteria

- `Pim.configure` block in `pim.rb` is the single initialization point
- No `configure_flat_record!` method exists
- `Pim::Config` contains only: `iso_dir`, `image_dir`, `serve_port`, `serve_profile`, `ventoy` block
- `Pim.root` returns Pathname
- FlatRecord stores data_paths as Pathname internally
- `BuildConfig` class is removed
- `LocalBuilder` reads build attrs from Build model
- `Profile::SHARED_PROFILES_DIR` constant is removed
- `pim new` template generates slim `pim.rb` with nested F/R config
- All specs pass

