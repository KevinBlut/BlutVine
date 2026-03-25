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

# Load shared logic and set up standardized paths
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

    # We still check for domsub/gn_args stamps because patch.sh writes them
    stamp_exists "domsub" || \
        die "Patching phase (domsub) not completed. Run patch.sh first."

    stamp_exists "gn_args" || \
        die "GN args not written. Run patch.sh first."

    # Check for build tools
    if ! command -v ninja >/dev/null 2>&1; then
        die "ninja not found. Install with: sudo apt install ninja-build"
    fi
}

# ── clean out/ ────────────────────────────────────────────────────────────────

clean_output() {
    log "Cleaning out/ directory..."
    rm -rf "${_src_dir}/out"
    clear_stamp "gn_args"
    clear_stamp "toolchain"

    # Re-write args.gn by calling patch.sh's write_gn_args equivalent
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

    # 1. Optional Clean
    if $_clean; then
        clean_output
    fi

    # 2. Ensure depot_tools in PATH (required for gn and toolchain scripts)
    ensure_depot_tools

    # 3. Setup toolchain (clang, rust, sysroot) — only if not already done
    if ! stamp_exists "toolchain" || $_force; then
        setup_toolchain
        write_stamp "toolchain"
    else
        log "Toolchain already set up, skipping. (--force to redo)"
    fi

    # 4. Generate build files
    # This uses the gn_gen function from shared.sh
    gn_gen

    # 5. Compile using maximum available cores
    # We use run_build from shared.sh which is updated to use autoninja
    run_build

    echo ""
    log "Build complete!"
    log "Binary location: ${_out_dir}/chrome"
}

main "$@"
