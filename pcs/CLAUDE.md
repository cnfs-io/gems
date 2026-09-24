# pcs

Takes a site's bare-metal machines from "on the network" to "installed", from a
control plane (Raspberry Pi). Built on termino (framework) and flat_record (YAML ORM).

**Start with `PROGRESS.md`.** It holds the decisions, what's done, the build order, where
every related repo lives, and working conventions. Two rules in particular:

- Other people's uncommitted work lives in this monorepo (e.g. `pim/`). Stage only with a
  path (`git add -- pcs`) and never commit.
- Run specs with `BUNDLE_GEMFILE=$PWD/Gemfile bundle exec rspec` from this directory.
