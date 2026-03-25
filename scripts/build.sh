#!/bin/bash
# build.sh
set -euo pipefail
_clean=false
for arg in "$@"; do [ "$arg" == "--clean" ] && _clean=true; done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.sh"
setup_paths

main() {
    if $_clean; then
        log "Cleaning build directory..."
        rm -rf "${_out_dir}"
        bash "$(dirname "${BASH_SOURCE[0]}")/patch.sh" --force
    fi

    setup_toolchain
    log "Generating GN files..."
    gn gen "${_out_dir}"
    log "Starting Ninja compile..."
    autoninja -C "${_out_dir}" chrome chromedriver
}
main
