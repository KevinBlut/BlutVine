#!/bin/bash
# fetch.sh - Pulls Chromium source
set -euo pipefail
_force=false
for arg in "$@"; do [ "$arg" == "--force" ] && _force=true; done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.sh"
setup_paths
ensure_depot_tools

main() {
    if $_force; then
        log "Cleaning existing source..."
        rm -rf "${_src_dir}" "${_build_dir}/chromium_version.txt"
        rm -f "${_src_dir}/"*.stamp
    fi

    if stamp_exists "gclient_synced" && ! $_force; then
        log "Source already synced. Skipping."
        exit 0
    fi

    log "Fetching latest stable version..."
    local ver
    ver=$(curl -fsSL "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=1" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['version'])")
    echo "$ver" > "${_build_dir}/chromium_version.txt"

    cat > "${_build_dir}/.gclient" <<GCLIENT
solutions = [{ "name": "src", "url": "https://chromium.googlesource.com/chromium/src.git@refs/tags/${ver}", "managed": False }]
GCLIENT

    cd "${_build_dir}"
    gclient sync --nohooks --no-history --force --with_branch_heads --with_tags -D
    write_stamp "gclient_synced"
}
main
