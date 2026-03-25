#!/bin/bash
# patch.sh - Applies Bifrost fingerprinting patches (Excludes 013, 015)
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
        log "Applying custom C++ patches (skipping 013 and 015)..."
        
        for p in "${_patch_dir}/"*.patch; do
            _patch_name=$(basename "$p")
            
            # Exclusion logic for 013 and 015
            if [[ "$_patch_name" == *"013"* ]] || [[ "$_patch_name" == *"015"* ]]; then
                info "Skipping excluded patch: $_patch_name"
                continue
            fi
            
            git apply --ignore-whitespace "$p" || echo "Warning: Patch $_patch_name failed to apply."
        done
        write_stamp "patched"
    fi

    log "Writing GN build arguments..."
    mkdir -p "${_out_dir}"
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
