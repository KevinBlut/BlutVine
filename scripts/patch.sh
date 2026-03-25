#!/bin/bash
# patch.sh - Applies Bifrost fingerprinting patches
set -euo pipefail
_force=false
for arg in "$@"; do [ "$arg" == "--force" ] && _force=true; done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.sh"
setup_paths
_patch_dir="${HOME}/BlutVine/fingerprint-chromium"

main() {
    if stamp_exists "patched" && ! $_force; then
        log "Patches already applied. Skipping."
    else
        cd "${_src_dir}"
        log "Applying custom C++ patches..."
        # Example of the batch application
        for p in "${_patch_dir}/"*.patch; do
            git apply --ignore-whitespace "$p" || echo "Warning: Patch $p failed to apply cleanly."
        done
        write_stamp "patched"
    fi

    log "Writing GN build arguments..."
    mkdir -p "${_out_dir}"
    # Fix: is_component_build=false for Official Build compatibility
    cat > "${_out_dir}/args.gn" <<GN_ARGS
is_debug = false
is_official_build = true
symbol_level = 0
is_component_build = false
use_thin_lto = true
use_lld = true
target_cpu = "${_build_arch}"
v8_target_cpu = "${_build_arch}"
GN_ARGS
    write_stamp "gn_args"
}
main
