#!/bin/bash
# build.sh - Toolchain setup and Ninja compilation
set -euo pipefail
_clean=false
for arg in "$@"; do [ "$arg" == "--clean" ] && _clean=true; done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.sh"
setup_paths

main() {
    if $_clean; then
        log "Wiping output directory..."
        rm -rf "${_out_dir}"
        bash "${_root}/scripts/patch.sh" --force
    fi

    setup_toolchain

    log "Generating build files..."
    gn gen "${_out_dir}"

    log "Starting Ninja build..."
    autoninja -C "${_out_dir}" chrome chromedriver
}
main
