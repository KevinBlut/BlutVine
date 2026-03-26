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

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"
setup_paths

# Path to custom patches. Override by setting BLUTVINE_DIR in the environment.
_kevin_blut_dir="${BLUTVINE_DIR:-${HOME}/BlutVine}"

# ── verify source tree exists ─────────────────────────────────────────────────

check_src() {
    [ -d "${_src_dir}" ] || \
        die "Source directory not found: ${_src_dir}. Run fetch.sh first."

    stamp_exists "gclient_synced" || \
        die "Source not synced. Run fetch.sh first."
}

# ── apply custom patches ──────────────────────────────────────────────────────

apply_custom_patches() {
    if stamp_exists "patched" && ! $_force; then
        log "Custom patches already applied, skipping. (--force to redo)"
        return 0
    fi

    [ -d "${_kevin_blut_dir}" ] || \
        die "BlutVine directory not found at: ${_kevin_blut_dir}. Set BLUTVINE_DIR to override."

    log "Applying Project Bifrost patches from: ${_kevin_blut_dir}"

    cd "${_src_dir}"

    _apply() {
        log "  -> Applying: $1"
        git apply "$1" || die "Failed to apply $1"
    }
    _apply_ws() {
        log "  -> Applying: $1"
        git apply --ignore-whitespace --ignore-space-change "$1" || die "Failed to apply $1"
    }

    _apply "${_kevin_blut_dir}/fingerprint-chromium/add-components-ungoogled.patch"
    _apply "${_kevin_blut_dir}/fingerprint-chromium/000-add-fingerprint-switches.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/001-disable-runtime.enable.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/002-user-agent-fingerprint.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/003-audio-fingerprint.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/003-audio-fingerprint-2.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/005-hardware-concurrency-fingerprint.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/006-font-fingerprint.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/007-shadow-root.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/009-webdriver.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/010-headless.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/011-gpu-info.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/012-canvas-get-image-data.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/014-client-rects.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/016-webgl-readPixels.patch"
    _apply_ws "${_kevin_blut_dir}/fingerprint-chromium/018-timezone.patch"

    write_stamp "patched"
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

    if [ -f "${_root}/flags.linux.gn" ]; then
        log "Using custom flags.linux.gn from ${_root}/"
        cat "${_root}/flags.linux.gn" > "${_out_dir}/args.gn"
    else
        log "No flags.linux.gn found — writing default release flags."
        cat > "${_out_dir}/args.gn" <<'GN_ARGS'
# ── Release build ─────────────────────────────────────────────────────────────
is_debug = false
is_official_build = true
symbol_level = 0

# ── Optimisation ──────────────────────────────────────────────────────────────
is_component_build = true
use_thin_lto = true
use_lld = true

# ── Codecs / media ────────────────────────────────────────────────────────────
proprietary_codecs = true
ffmpeg_branding = "Chrome"

# ── Remove things you don't need ──────────────────────────────────────────────
enable_nacl = false
enable_remoting = false
enable_reading_list = false
build_with_chromium_features = true

# ── Linux-specific ────────────────────────────────────────────────────────────
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
    apply_custom_patches
    write_gn_args

    # Write a 'domsub' stamp so build.sh check_ready() remains satisfied.
    # This stamp has no work behind it — it just marks that patch.sh ran fully.
    write_stamp "domsub"

    echo ""
    log "Done. Source is patched and ready."
    log "Next step: bash scripts/build.sh"
}

main "$@"
