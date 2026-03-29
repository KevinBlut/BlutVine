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

echo ""
echo "Done. Source is at: ${_src_dir}"
