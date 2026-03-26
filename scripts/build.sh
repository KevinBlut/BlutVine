#!/bin/bash
# build.sh
# Downloads toolchain (clang, rust, sysroot), generates build files,
# and compiles chrome + chromedriver.
# Run after patch.sh.
#
# Usage:
#   bash scripts/build.sh            # normal build
#   bash scripts/build.sh --clean    # wipe out/ and rebuild
#   bash scripts/build.sh --force    # redo toolchain setup + rebuild
#
set -euo pipefail

_clean=false
_force=false
for arg in "$@"; do
    case "$arg" in
        --clean) _clean=true ;;
        --force) _force=true ;;
    esac
done

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"
setup_paths

# ── pre-flight checks ─────────────────────────────────────────────────────────

check_ready() {
    [ -d "${_src_dir}" ] || \
        die "Source directory not found. Run fetch.sh first."

    stamp_exists "gclient_synced" || \
        die "Source not synced. Run fetch.sh first."

    stamp_exists "patched" || \
        die "Patches not applied. Run patch.sh first."

    stamp_exists "domsub" || \
        die "Patching phase not completed. Run patch.sh first."

    stamp_exists "gn_args" || \
        die "GN args not written. Run patch.sh first."

    # Check for a usable build tool — mirrors the priority order in run_build()
    if [ ! -f "${_depot_tools_dir}/autoninja" ] && \
       ! command -v autoninja >/dev/null 2>&1 && \
       ! command -v ninja >/dev/null 2>&1; then
        die "No build tool found. Install ninja-build: sudo apt install ninja-build"
    fi
}

# ── clean out/ ────────────────────────────────────────────────────────────────

clean_output() {
    log "Cleaning out/ directory..."
    rm -rf "${_src_dir}/out"
    clear_stamp "gn_args"
    clear_stamp "toolchain"

    mkdir -p "${_out_dir}"
    log "Re-writing GN args after clean..."
    if [ -f "${_root}/flags.linux.gn" ]; then
        cat "${_root}/flags.linux.gn" > "${_out_dir}/args.gn"
    else
        cat > "${_out_dir}/args.gn" <<'GN_ARGS'
is_debug = false
is_official_build = true
symbol_level = 0
is_component_build = true
use_thin_lto = true
use_lld = true
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_nacl = false
enable_remoting = false
enable_reading_list = false
build_with_chromium_features = true
use_cups = true
use_pulseaudio = true
link_pulseaudio = true
GN_ARGS
    fi
    echo "target_cpu = \"${_build_arch}\""    >> "${_out_dir}/args.gn"
    echo "v8_target_cpu = \"${_build_arch}\"" >> "${_out_dir}/args.gn"
    write_stamp "gn_args"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
    local version
    version="$(get_cached_version)"

    log "build.sh — toolchain + compile Chromium ${version}"
    log "Clean: ${_clean} | Force: ${_force}"
    echo ""

    check_ready

    if $_clean; then
        clean_output
    fi

    ensure_depot_tools

    if ! stamp_exists "toolchain" || $_force; then
        setup_toolchain
        write_stamp "toolchain"
    else
        log "Toolchain already set up, skipping. (--force to redo)"
    fi

    gn_gen
    run_build

    echo ""
    log "Build complete!"
    log "Binary location: ${_out_dir}/chrome"
}

main "$@"
