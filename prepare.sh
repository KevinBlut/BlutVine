#!/bin/bash
# prepare.sh
# Fetches the complete Chromium source tree (including all DEPS),
# applies ungoogled-chromium patches, domain substitution, and writes GN args.
# Does NOT compile anything.
#
# Usage:
#   bash prepare.sh              # normal run
#   bash prepare.sh -c           # use git clone instead of tarball
#   bash prepare.sh --force      # clear stamps and re-run everything
#   bash prepare.sh -c --force   # clone mode + force
#
set -euo pipefail

# ── args ──────────────────────────────────────────────────────────────────────

clone=false
force=false
for arg in "$@"; do
    case "$arg" in
        -c)      clone=true ;;
        --force) force=true ;;
    esac
done

# ── load shared functions ─────────────────────────────────────────────────────

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_paths

# ── helpers ───────────────────────────────────────────────────────────────────

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── depot_tools ───────────────────────────────────────────────────────────────

ensure_depot_tools() {
    local depot_dir="${_build_dir}/depot_tools"
    if [ ! -d "${depot_dir}/.git" ]; then
        log "Cloning depot_tools..."
        git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools.git \
            "${depot_dir}"
    else
        log "depot_tools already present, updating..."
        git -C "${depot_dir}" pull --ff-only || true
    fi
    export PATH="${depot_dir}:${PATH}"
    export DEPOT_TOOLS_UPDATE=0
}

# ── gclient sync ──────────────────────────────────────────────────────────────
# Fills in all DEPS entries that the tarball omits.
# --nohooks skips toolchain downloads — those happen later in build.sh.

run_gclient_sync() {
    log "Running gclient sync to fetch remaining DEPS..."

    # Write .gclient config next to src/
    cat > "${_build_dir}/.gclient" <<'GCLIENT'
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
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
}

# ── known missing deps ────────────────────────────────────────────────────────
# Safety net for deps gclient occasionally misses.

fetch_known_missing() {
    log "Fetching known missing third_party deps..."

    declare -A _missing_deps=(
        ["third_party/catapult"]="https://chromium.googlesource.com/catapult"
        ["third_party/depot_tools"]="https://chromium.googlesource.com/chromium/tools/depot_tools"
        ["tools/clang"]="https://chromium.googlesource.com/chromium/src/tools/clang"
    )

    for subdir in "${!_missing_deps[@]}"; do
        local target="${_src_dir}/${subdir}"
        if [ ! -d "${target}" ]; then
            log "  cloning ${subdir}..."
            mkdir -p "$(dirname "${target}")"
            git clone --depth=1 "${_missing_deps[$subdir]}" "${target}" || \
                log "  WARNING: failed to clone ${subdir}, skipping"
        else
            log "  ${subdir} already present, skipping"
        fi
    done
}

# ── missing dir report ────────────────────────────────────────────────────────

report_missing() {
    local expected_dirs=(
        "base" "build" "chrome" "components" "content" "net" "ui" "v8"
        "third_party/abseil-cpp"
        "third_party/angle"
        "third_party/boringssl"
        "third_party/blink"
        "third_party/ffmpeg"
        "third_party/icu"
        "third_party/skia"
        "third_party/zlib"
        "tools/gn"
        "tools/clang"
    )

    local missing=()
    for d in "${expected_dirs[@]}"; do
        [ ! -d "${_src_dir}/${d}" ] && missing+=("$d")
    done

    if [ ${#missing[@]} -eq 0 ]; then
        log "All expected directories present."
    else
        echo ""
        echo "WARNING: The following expected directories are still missing:"
        for d in "${missing[@]}"; do echo "  - $d"; done
        echo ""
        echo "Check ${_build_dir}/gclient-sync.log for details."
    fi
}

# ── stamp helpers ─────────────────────────────────────────────────────────────

clear_stamps() {
    rm -f "${_src_dir}/.downloaded.stamp"
    rm -f "${_src_dir}/.patched.stamp"
    rm -f "${_src_dir}/.domsub.stamp"
    log "Stamps cleared."
}

# ── main ──────────────────────────────────────────────────────────────────────

log "prepare.sh — full source fetch + patch (no compilation)"
log "Clone mode: ${clone} | Force: ${force}"
echo ""

if $force; then
    log "Force mode: clearing all stamps..."
    clear_stamps
fi

# Step 1: depot_tools (needed for gclient)
log "Setting up depot_tools..."
ensure_depot_tools

# Step 2: fetch primary sources (tarball or clone)
log "Fetching primary sources..."
fetch_sources "$clone"

# Step 3: gclient sync to fill in what tarball misses
if [ ! -f "${_src_dir}/.gclient_synced.stamp" ]; then
    run_gclient_sync
    touch "${_src_dir}/.gclient_synced.stamp"
else
    log "gclient sync already done, skipping (use --force to redo)"
fi

# Step 4: fetch any remaining known-missing deps
fetch_known_missing

# Step 5: report anything still absent
report_missing

# Step 6: apply ungoogled-chromium patches
log "Applying ungoogled-chromium patches..."
apply_patches

# Step 7: domain substitution
log "Applying domain substitution..."
apply_domsub

# Step 8: write GN args
log "Writing GN args..."
write_gn_args

echo ""
echo "Done. Source is ready at: ${_src_dir}"
echo "Patches applied. No compilation was run."
echo "Next step: bash scripts/build.sh"
