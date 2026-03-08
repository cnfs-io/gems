---
objective: "Restructure the PIM project scaffold layout to cleanly separate data declarations (YAML) from builder components (scripts, templates)."
status: complete
---

# Layout Refactor Tier — PIM Project Structure

## Objective

Restructure the PIM project scaffold layout to cleanly separate data declarations (YAML) from builder components (scripts, templates). After this tier, `pim new` generates the new layout, all path references across the codebase resolve correctly, and existing specs pass against the new structure.

**The question this tier answers:** Does the new layout give us a cleaner separation of concerns without breaking the FlatRecord integration or builder pipeline?

## Target Layout

```
myproject/
├── pim.rb
├── data/
│   ├── builds/default.yml
│   ├── isos/default.yml
│   ├── profiles/default.yml
│   └── targets/default.yml
├── resources/
│   ├── post_installs/default.sh
│   ├── preseeds/default.cfg.erb
│   ├── scripts/{base,finalize}.sh
│   └── verifications/default.sh
```

### Current Layout (being replaced)

```
myproject/
├── pim.yml
├── builds.yml
├── isos.yml
├── profiles.yml
├── targets.yml
├── installs.d/default.sh
├── preseeds.d/default.cfg.erb
├── scripts.d/{base,finalize}.sh
└── verifications.d/default.sh
```

## Key Design Decisions

- **`data/` holds all YAML declarations** — builds, isos, profiles, targets. Each resource gets its own subdirectory so FlatRecord can glob `data/<resource>/*.yml` for multi-file support.
- **`resources/` holds all executable/template content** — the "how" of builds. Replaces the `.d` suffix convention.
- **`post_installs/` replaces `installs.d/`** — clearer name: these are late-command scripts that run during preseed post-installation phase.
- **`builders/scripts/` replaces `scripts.d/`** — SSH provisioning scripts that run after OS install inside the QEMU VM.
- **FlatRecord data_paths change** — currently points at project root (where `builds.yml` etc. live). Must now point at `data/` subdirectory so `source "builds"` resolves to `data/builds/*.yml`.
- **Profile data_paths also change** — shared profiles path stays, but project path becomes `data/profiles/`.
- **`pim.rb` at root** — Ruby DSL config, also serves as the project identity marker.

## Completion Criteria

- [ ] `pim new` generates the new layout
- [ ] FlatRecord data_paths resolve correctly against `data/` subdirectories
- [ ] Profile template resolution uses `resources/` paths (preseeds, post_installs, verifications)
- [ ] ScriptLoader resolves scripts from `resources/scripts/`
- [ ] Server serves preseeds from `resources/preseeds/` and post_installs from `resources/post_installs/`
- [ ] LocalBuilder pipeline works with new paths
- [ ] Verifier finds verification scripts in `resources/verifications/`
- [ ] All existing specs pass (updated for new paths)
- [ ] `pim console` can load data from new layout
- [ ] CLAUDE.md updated with new layout documentation

## Plans

| # | Name | Description | Status |
|---|------|-------------|--------|
| 01 | scaffold-and-templates | Restructure template directory and Project class for new layout | ✅ |
| 02 | data-paths | Update FlatRecord data_paths and model source resolution for `data/` | ✅ |
| 03 | builder-paths | Update Profile, ScriptLoader, Server, LocalBuilder, Verifier for `builders/` paths | ✅ |
| 04 | specs-and-docs | Update all specs for new layout, update CLAUDE.md | ✅ |
| 05 | boot-and-scaffold | Extract boot.rb (detection + boot!) and new/scaffold.rb (scaffolding), rename builders→resources, delete Project class |
| 06 | ruby-config-dsl | Replace pim.yml with pim.rb Ruby DSL, rewrite Config/BuildConfig/VentoyConfig |
| 07 | centralize-boot-cleanup | Single boot! entry point, remove scattered configure_flat_record! calls, final CLAUDE.md update |

## Dependencies

- Plans are sequential (01 → 02 → 03 → 04 → 05 → 06 → 07)
- Plans 01-04: layout restructure (complete)
- Plans 05-07: architecture refactor (boot, config DSL, centralization)
- No external gem changes required — FlatRecord already supports directory-based data_paths

## Risk

- **FlatRecord source resolution**: `source "builds"` currently resolves to `<data_path>/builds.yml`. With the new layout, data_path becomes `<project>/data` and the source dir is `builds/`, containing `default.yml`. Need to verify FlatRecord handles `<data_path>/builds/default.yml` correctly (it should — it globs `*.yml` in the source directory).
- **Shared profiles merge order**: Profile data_paths include both the shared provisioning dir and the project `data/profiles/` dir. Must maintain correct merge precedence.
- **pim.rb as marker**: Changing the project marker from `pim.yml` to `pim.rb` means `load`ing user Ruby code at boot. Acceptable for a personal tool.
- **Config migration**: Any existing projects with `pim.yml` will need manual migration to `pim.rb`. No automated migration — document the change.

