#!/bin/bash
# patch.sh
# Applies custom fingerprinting patches from BlutVine using the series file.
# Run after fetch.sh, before build.sh.
#
# The series file at ${BLUTVINE_DIR}/series (default: ~/BlutVine/series) lists
# each patch path relative to the BlutVine root, one per line.
# Lines starting with # and blank lines are ignored.
#
set -euo pipefail

_force=false
for arg in "$@"; do
    case "$arg" in
        --force) _force=true ;;
    esac
done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"
setup_paths

# ── verify source tree exists ─────────────────────────────────────────────────

check_src() {
    [ -d "${_src_dir}" ] || \
        die "Source directory not found: ${_src_dir}. Run fetch.sh first."
    stamp_exists "gclient_synced" || \
        die "Source not synced. Run fetch.sh first."
}

# ── apply patches via series file ─────────────────────────────────────────────

apply_patches_from_series() {
    if stamp_exists "patched" && ! $_force; then
        log "Patches already applied, skipping. (--force to redo)"
        return 0
    fi

    [ -d "${_blutvine_dir}" ] || \
        die "BlutVine directory not found: ${_blutvine_dir}. Set BLUTVINE_DIR to override."

    local series_file="${_blutvine_dir}/series"
    [ -f "$series_file" ] || \
        die "series file not found: ${series_file}"

    log "Applying patches from series: ${series_file}"
    cd "${_src_dir}"

    local applied=0
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip blank lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        local patch_file="${_blutvine_dir}/${line}"
        [ -f "$patch_file" ] || die "Patch listed in series not found: ${patch_file}"

        log "  -> Applying: ${line}"
        git apply --ignore-whitespace --ignore-space-change "$patch_file" \
            || die "Failed to apply patch: ${patch_file}"
        (( applied++ )) || true
    done < "$series_file"

    log "Applied ${applied} patch(es) successfully."
    write_stamp "patched"
}

# ── GN args ───────────────────────────────────────────────────────────────────

write_gn_args() {
    if stamp_exists "gn_args" && ! $_force; then
        log "GN args already written, skipping."
        return 0
    fi

    log "Writing GN build arguments..."
    mkdir -p "${_out_dir}"

    if [ -f "${_root}/flags.linux.gn" ]; then
        log "Using custom flags.linux.gn from ${_root}/"
        cat "${_root}/flags.linux.gn" > "${_out_dir}/args.gn"
    else
        log "No flags.linux.gn found — writing default release flags."
        cat > "${_out_dir}/args.gn" <<'GN_ARGS'
is_debug = false
symbol_level = 0
is_component_build = true
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_nacl = false
use_cups = true
use_pulseaudio = true
link_pulseaudio = true
GN_ARGS
    fi

    echo "target_cpu = \"${_build_arch}\"" >> "${_out_dir}/args.gn"
    echo "v8_target_cpu = \"${_build_arch}\"" >> "${_out_dir}/args.gn"

    write_stamp "gn_args"
    log "GN args written to ${_out_dir}/args.gn"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
    log "Starting patch.sh (Project Bifrost)"

    check_src
    apply_patches_from_series
    write_gn_args

    # 'domsub' stamp satisfies build.sh check_ready() — marks patch.sh ran fully
    write_stamp "domsub"

    echo ""
    log "Done. Source is patched and ready."
    log "Next step: bash scripts/build.sh"
}

main "$@"
