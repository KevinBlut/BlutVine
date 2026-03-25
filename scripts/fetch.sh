#!/bin/bash
# fetch.sh
# Fetches the latest stable Chromium source tree via gclient sync.
# Does NOT apply patches or compile anything.
#
# Usage:
#   bash scripts/fetch.sh            # fetch latest stable
#   bash scripts/fetch.sh --force    # clear stamps and re-fetch everything
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

# ── fetch latest stable version number ───────────────────────────────────────

fetch_version() {
    log "Fetching latest stable Chromium version..."
    local version
    version="$(get_latest_stable_version)"
    log "Latest stable: ${version}"
    echo "$version" > "${_build_dir}/chromium_version.txt"
}

# ── gclient sync ──────────────────────────────────────────────────────────────
# Checks out src/ at the pinned version tag and syncs all DEPS.
# --nohooks: skip toolchain downloads (handled separately in build.sh)
# --no-history: shallow fetch per dep (saves disk + time)
# -D: delete deps that are no longer in DEPS

run_gclient_sync() {
    local version="$1"
    log "Running gclient sync for Chromium ${version}..."

    # Write .gclient file next to src/ pointing at the pinned version tag.
    # gclient will create and manage src/ itself — do NOT pre-create it.
    cat > "${_build_dir}/.gclient" <<GCLIENT
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git@refs/tags/${version}",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
GCLIENT

    cd "${_build_dir}"
    gclient sync \
        --nohooks \
        --no-history \
        --force \
        --with_branch_heads \
        --with_tags \
        -D \
        2>&1 | tee "${_build_dir}/gclient-sync.log"

    log "gclient sync complete."
}

# ── sanity check ──────────────────────────────────────────────────────────────

check_src_exists() {
    if [ ! -d "${_src_dir}" ]; then
        die "Expected source directory not found after sync: ${_src_dir}"
    fi
    if [ ! -f "${_src_dir}/BUILD.gn" ]; then
        die "Source directory looks incomplete — BUILD.gn missing in ${_src_dir}"
    fi
    log "Source tree looks good: ${_src_dir}"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
    log "fetch.sh — download latest stable Chromium source via gclient (no compile)"
    log "Force: ${_force}"
    echo ""

    if $_force; then
        log "Force mode: clearing all stamps and removing existing src/..."
        clear_all_stamps
        rm -f "${_build_dir}/chromium_version.txt"
        # Remove src/ so gclient can check it out cleanly
        rm -rf "${_src_dir}"
    fi

    # Already fully fetched?
    if stamp_exists "gclient_synced" && ! $_force; then
        local cached_ver
        cached_ver="$(get_cached_version)"
        log "Source already fetched (version ${cached_ver}). Use --force to re-fetch."
        check_src_exists
        exit 0
    fi

    # Requirements check
    for cmd in curl git python3; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required tool not found: $cmd"
    done

    # Step 1: Get version
    fetch_version
    local version
    version="$(get_cached_version)"

    # Step 2: depot_tools (needed for gclient)
    ensure_depot_tools

    # Step 3: gclient sync — checks out src/ and all DEPS at the pinned tag
    run_gclient_sync "$version"
    mkdir -p "${_src_dir}"
    write_stamp "gclient_synced"

    # Step 4: Sanity check
    check_src_exists

    echo ""
    log "Done. Chromium ${version} source is at: ${_src_dir}"
    log "Next step: bash scripts/patch.sh"
}

main "$@"
