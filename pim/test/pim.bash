# pim/test/pim.bash
# Shared setup for all pim BATS tests
#
# Provides:
#   PIM_CMD       - path to the pim binstub
#   PIM_GEM       - path to the pim gem root
#   Sets XDG_CONFIG_HOME to the package's config dir for test isolation

# Resolve paths relative to the pim gem
PIM_GEM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIM_GEMS_ROOT="$(cd "$PIM_GEM/.." && pwd)"

# Use the binstub (assumes install.sh has been run)
PIM_CMD="${PIM_GEMS_ROOT}/bin/pim"

# Fallback to bundler exec if binstub doesn't exist
if [[ ! -x "$PIM_CMD" ]]; then
  PIM_CMD="bundle exec --gemfile=${PIM_GEMS_ROOT}/Gemfile pim"
fi

# Use the original ppm package's config for test fixtures
# Adjust this path if config files move into the gem
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Use real cache and data dirs
# XDG_CACHE_HOME  -> defaults to ~/.cache       (ISO downloads)
# XDG_DATA_HOME   -> defaults to ~/.local/share  (images + registry)

# Detect host architecture for architecture-dependent tests
case "$(uname -m)" in
  arm64|aarch64) HOST_ARCH="arm64" ;;
  x86_64|amd64)  HOST_ARCH="amd64" ;;
  *)             HOST_ARCH="$(uname -m)" ;;
esac
