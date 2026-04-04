#!/bin/bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_paths
apply_blutvine_patches