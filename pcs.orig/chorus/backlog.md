# Backlog — PCS

Ideas not yet planned into a tier. When a real use case materializes, assign to the appropriate tier.

---

## Extract shared platform gem (`cnfs-platform` or `ppm-platform`)

**Description:** PCS and PIM are converging on shared primitives: `Platform::Arch`, `Platform::Os`, the `Profile` model, preseed/kickstart templates, XDG conventions, boot patterns. Rather than duplicating or creating a dependency from PIM → PCS, extract a small toolkit gem (akin to ActiveSupport) containing just the shared data and utility modules.

**Contents (candidates):**
- `Platform::Arch` + `architectures.yml`
- `Platform::Os` + `operating_systems.yml`
- `Profile` model (currently implemented independently in both gems)
- Preseed/kickstart/autoinstall templates (the ERB files, not the rendering logic)
- Shared boot pattern (`root`, `boot!`, `configure`)

**Does NOT contain:** Host inventory, services, networking, image building, CLI, commands.

**Trigger:** When PIM needs `Platform::Arch` or `Platform::Os`. At that point, extraction is mechanical — move files, publish gem, update gemspecs.

**Rationale for deferral:** PIM doesn't need this yet. Building it now would be premature abstraction. Finish the e2e tier with everything in PCS, then extract when the second consumer appears.
