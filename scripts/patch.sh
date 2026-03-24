#!/bin/bash
# patch.sh
# Applies custom fingerprinting patches from the KevinBlut repository.
# Run after fetch.sh, before build.sh.

set -euo pipefail

_force=false
for arg in "$@"; do
    case "$arg" in
        --force) _force=true ;;
    esac
done

# 1. Load shared logic and set up standardized paths (_src_dir, _root, etc.)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"
setup_paths

# 2. Define the path to your custom patches (relative to your home directory)
_kevin_blut_dir="${HOME}/KevinBlut/fingerprint-chromium"

# ── verify source tree exists ─────────────────────────────────────────────────

check_src() {
    [ -d "${_src_dir}" ] || \
        die "Source directory not found: ${_src_dir}. Run fetch.sh first."
    
    stamp_exists "downloaded" || \
        die "Source not fully downloaded. Run fetch.sh first."
}

# ── apply custom patches ──────────────────────────────────────────────────────

apply_custom_patches() {
    # Utilizing shared stamp_exists helper
    if stamp_exists "patched" && ! $_force; then
        log "Custom patches already applied, skipping. (--force to redo)"
        return 0
    fi

    [ -d "${_kevin_blut_dir}" ] || die "KevinBlut directory not found at: ${_kevin_blut_dir}"
    [ -f "${_kevin_blut_dir}/series" ] || die "No 'series' file found in ${_kevin_blut_dir}."

    log "Applying Project Bifrost patches from: ${_kevin_blut_dir}"

    cd "${_src_dir}"
    while IFS= read -r patch_file || [ -n "$patch_file" ]; do
        [[ -z "$patch_file" || "$patch_file" =~ ^# ]] && continue

        log "  -> Applying: ${patch_file}"
        patch -p1 < "${_kevin_blut_dir}/${patch_file}" || die "Failed to apply ${patch_file}"
    done < "${_kevin_blut_dir}/series"

    # Utilizing shared write_stamp helper
    write_stamp "patched"
    
    # We still write 'domsub' because build.sh 'check_ready' expects it
    write_stamp "domsub" 
    log "Patching process successful."
}

# ── GN args ───────────────────────────────────────────────────────────────────

write_gn_args() {
    if stamp_exists "gn_args" && ! $_force; then
        log "GN args already written, skipping."
        return 0
    fi

    log "Writing GN build arguments..."
    mkdir -p "${_out_dir}"

    # Utilizing the flags file in your project root
    if [ -f "${_root}/flags.linux.gn" ]; then
        cat "${_root}/flags.linux.gn" > "${_out_dir}/args.gn"
    else
        log "WARNING: flags.linux.gn not found. Creating minimal args.gn."
        touch "${_out_dir}/args.gn"
    fi

    # Using the _build_arch variable from shared.sh
    echo "target_cpu = \"${_build_arch}\"" >> "${_out_dir}/args.gn"
    echo "v8_target_cpu = \"${_build_arch}\"" >> "${_out_dir}/args.gn"

    write_stamp "gn_args"
    log "GN args written to ${_out_dir}/args.gn"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
    log "Starting patch.sh (Project Bifrost)"
    
    check_src
    apply_custom_patches
    write_gn_args

    echo ""
    log "Done. Source is patched and ready."
    log "Next step: bash scripts/build.sh"
}

main "$@"