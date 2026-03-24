#!/bin/bash
# fetch.sh
# Fetches the latest stable Chromium source tree including all DEPS.
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

# ── download source tarball ───────────────────────────────────────────────────
# Official Chromium tarballs are published at:
# https://commondatastorage.googleapis.com/chromium-browser-official/
# They bundle most third_party deps but not everything in DEPS.

fetch_tarball() {
    local version="$1"
    local tarball="chromium-${version}.tar.xz"
    local url="https://commondatastorage.googleapis.com/chromium-browser-official/${tarball}"
    local dest="${_dl_cache}/${tarball}"

    if [ -f "${dest}" ]; then
        log "Tarball already cached: ${tarball}"
    else
        log "Downloading ${tarball} (~3-4 GB, this will take a while)..."
        curl -fL --progress-bar -o "${dest}.part" "$url"
        mv "${dest}.part" "${dest}"
        log "Download complete."
    fi

    log "Unpacking tarball into ${_src_dir}..."
    mkdir -p "${_src_dir}"
    tar -xf "${dest}" \
        --strip-components=1 \
        -C "${_src_dir}" \
        --checkpoint=10000 \
        --checkpoint-action=echo="  extracted %{r}T..."
    log "Unpack complete."
}

# ── gclient sync ──────────────────────────────────────────────────────────────
# Fills in all DEPS entries the tarball omits.
# --nohooks: skip toolchain downloads (handled separately in build.sh)
# --no-history: shallow fetch per dep (saves disk + time)
# -D: delete deps that are no longer in DEPS

run_gclient_sync() {
    local version="$1"
    log "Running gclient sync for Chromium ${version}..."

    # Write .gclient file next to src/ pointing at the pinned version tag
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

# ── main ──────────────────────────────────────────────────────────────────────

main() {
    log "fetch.sh — download latest stable Chromium source (no compile)"
    log "Force: ${_force}"
    echo ""

    if $_force; then
        log "Force mode: clearing all stamps..."
        clear_all_stamps
        rm -f "${_build_dir}/chromium_version.txt"
    fi

    # already fully fetched?
    if stamp_exists "downloaded" && stamp_exists "gclient_synced" && ! $_force; then
        local cached_ver
        cached_ver="$(get_cached_version)"
        log "Source already fetched (version ${cached_ver}). Use --force to re-fetch."
        report_missing
        exit 0
    fi

    # requirements check
    for cmd in curl git python3 tar; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required tool not found: $cmd"
    done

    # step 1: get version
    fetch_version
    local version
    version="$(get_cached_version)"

    # step 2: depot_tools (needed for gclient)
    ensure_depot_tools

    # step 3: download + unpack tarball
    if ! stamp_exists "downloaded" || $_force; then
        fetch_tarball "$version"
        write_stamp "downloaded"
    else
        log "Tarball already unpacked, skipping."
    fi

    # step 4: gclient sync to fill in what tarball omits
    if ! stamp_exists "gclient_synced" || $_force; then
        run_gclient_sync "$version"
        write_stamp "gclient_synced"
    else
        log "gclient sync already done, skipping. (--force to redo)"
    fi

    # step 5: sanity check
    report_missing

    echo ""
    log "Done. Chromium ${version} source is at: ${_src_dir}"
    log "Next step: bash scripts/patch.sh"
}

main "$@"
