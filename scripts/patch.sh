#!/bin/bash
# patch.sh
set -euo pipefail
_force=false
for arg in "$@"; do [ "$arg" == "--force" ] && _force=true; done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared.sh"
setup_paths

# FIX: Set the root to BlutVine so the paths in 'series' resolve correctly
_blutvine_root="${HOME}/BlutVine"
_series_file="${_blutvine_root}/series"

main() {
    if stamp_exists "patched" && ! $_force; then
        log "Patches already applied. Skipping."
    else
        [ -f "$_series_file" ] || die "Series file not found at $_series_file"
        
        cd "${_src_dir}"
        log "Applying patches from: $_series_file"

        while IFS= read -r patch_file || [ -n "$patch_file" ]; do
            [[ -z "$patch_file" || "$patch_file" == \#* ]] && continue
            patch_file=$(echo "$patch_file" | xargs)

            log "Applying: $patch_file"
            # FIX: Use _blutvine_root here so it matches the paths in your series file
            git apply --ignore-whitespace "${_blutvine_root}/${patch_file}" || die "Failed on: $patch_file"
        done < "$_series_file"
        
        write_stamp "patched"
    fi
    
    # ... (rest of the GN args logic)
}
main
