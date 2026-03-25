#!/bin/bash
# patch.sh
set -euo pipefail
_force=false
for arg in "$@"; do [ "$arg" == "--force" ] && _force=true; done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.sh"
setup_paths

# Path updated to BlutVine/series
_kevin_blut_dir="${HOME}/BlutVine"
_patch_dir="${_kevin_blut_dir}/fingerprint-chromium"
_series_file="${_kevin_blut_dir}/series"

main() {
    if stamp_exists "patched" && ! $_force; then
        log "Patches already applied. Skipping."
    else
        [ -f "$_series_file" ] || die "Series file not found at $_series_file"
        
        cd "${_src_dir}"
        log "Applying patches from: $_series_file"

        while IFS= read -r patch_file || [ -n "$patch_file" ]; do
            # Skip empty lines or comments
            [[ -z "$patch_file" || "$patch_file" == \#* ]] && continue
            
            # Trim whitespace
            patch_file=$(echo "$patch_file" | xargs)

            log "Applying: $patch_file"
            git apply --ignore-whitespace "${_patch_dir}/${patch_file}" || die "Failed on: $patch_file"
        done < "$_series_file"
        
        write_stamp "patched"
    fi

    log "Writing GN arguments..."
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
