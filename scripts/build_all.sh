#!/bin/bash
set -euo pipefail

echo "Installing bootstrap dependencies..."
sudo apt-get update -qq
sudo apt-get install -y git curl python3 lsb-release

sudo systemctl daemon-reexec 2>/dev/null || true

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_paths
setup_depot_tools
fetch_chromium
apply_blutvine_patches
export PATH="${_depot_tools_dir}:${PATH}"
export PATH="${_depot_tools_dir}/.cipd_bin:${PATH}"
write_gn_args
setup_sccache
gn_gen
maybe_build
