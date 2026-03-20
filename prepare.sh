#!/bin/bash
set -euo pipefail

clone=false
if [[ "${1:-}" == "-c" ]]; then
    clone=true
fi

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_paths

echo "==> Fetching sources..."
fetch_sources "$clone"

echo "==> Applying ungoogled-chromium patches..."
apply_patches

echo "==> Applying domain substitution..."
apply_domsub

echo "==> Writing GN args (no compile)..."
write_gn_args

echo ""
echo "Done. Source is ready at: ${_src_dir}"
echo "Patches applied. No compilation was run."
