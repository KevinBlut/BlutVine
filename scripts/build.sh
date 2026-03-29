#!/bin/bash
set -euo pipefail

# Only install the bare minimum needed to bootstrap depot_tools and run
# install-build-deps.sh — that script handles the rest of the system deps.
echo "Installing bootstrap dependencies..."
sudo apt-get update -qq
sudo apt-get install -y git curl python3 lsb-release

# Restart systemd so updated libs don't cause "daemon using outdated libraries"
sudo systemctl daemon-reexec 2>/dev/null || true

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_paths
setup_depot_tools

# clean out/ before build
rm -rf "${_out_dir}" || true

fetch_chromium
apply_blutvine_patches
write_gn_args
setup_sccache
gn_gen
maybe_build
