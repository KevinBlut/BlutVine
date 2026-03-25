#!/bin/bash
# shared.sh
# Base functions sourced by fetch.sh, patch.sh, and build.sh
set -euo pipefail

# ── logging ───────────────────────────────────────────────────────────────────

log()  { echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── repo root ─────────────────────────────────────────────────────────────────

repo_root() {
    # Allow the caller (setup-and-build.sh) to pin the root explicitly.
    # This prevents BASH_SOURCE[0]-based resolution from returning the wrong
    # directory when scripts are copied to a different location mid-run.
    if [ -n "${CHROME_ROOT:-}" ]; then
        echo "$CHROME_ROOT"
        return
    fi
    local _base
    _base="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    cd "${_base}/.." >/dev/null 2>&1 && pwd
}

# ── architecture ──────────────────────────────────────────────────────────────

setup_arch() {
    _host_arch=$(uname -m)
    case "$_host_arch" in
        x86_64)  _host_arch="x64"  ;;
        aarch64) _host_arch="arm64" ;;
    esac

    _build_arch="${ARCH:-$_host_arch}"
    if [ "$_build_arch" = "x86_64" ]; then
        _build_arch="x64"
    fi
}

# ── paths ─────────────────────────────────────────────────────────────────────

setup_paths() {
    _root="$(repo_root)"
    _scripts_dir="${_root}/scripts"
    
    # Pathing standardized to: ~/Chrome/build/src
    _build_dir="${_root}/build"
    _src_dir="${_build_dir}/src"
    _out_dir="${_src_dir}/out/Default"
    
    _dl_cache="${_build_dir}/download_cache"
    _depot_tools_dir="${_build_dir}/depot_tools"

    setup_arch
    mkdir -p "${_dl_cache}" "${_build_dir}"
}

# ── chromium version ──────────────────────────────────────────────────────────

get_latest_stable_version() {
    local api_url="https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=1"
    local version
    version=$(curl -fsSL "$api_url" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data[0]['version'])
" 2>/dev/null) || die "Failed to fetch latest stable Chromium version"
    echo "$version"
}

get_cached_version() {
    local ver_file="${_build_dir}/chromium_version.txt"
    [ -f "$ver_file" ] || die "No cached version found. Run fetch.sh first."
    cat "$ver_file"
}

# ── depot_tools ───────────────────────────────────────────────────────────────

ensure_depot_tools() {
    if [ ! -d "${_depot_tools_dir}/.git" ]; then
        log "Cloning depot_tools..."
        git clone --depth=1 \
            https://chromium.googlesource.com/chromium/tools/depot_tools.git \
            "${_depot_tools_dir}"
    else
        log "Updating depot_tools..."
        git -C "${_depot_tools_dir}" pull --ff-only || true
    fi
    export PATH="${_depot_tools_dir}:${PATH}"
    export DEPOT_TOOLS_UPDATE=0
    export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1
}

# ── toolchain ─────────────────────────────────────────────────────────────────

setup_toolchain() {
    log "Setting up toolchain (clang + rust + sysroot)..."

    # Chromium 146 uses specific Python scripts for toolchain updates
    if [ "$_host_arch" = x64 ]; then
        log "Downloading prebuilt Clang and Rust..."
        python3 "${_src_dir}/tools/rust/update_rust.py"
        python3 "${_src_dir}/tools/clang/scripts/update.py"
    else
        log "Non-x64 host detected. Building toolchain from source..."
        python3 "${_src_dir}/tools/clang/scripts/build.py" --without-fuchsia --without-android
    fi

    # Install the Debian-based sysroot for linking
    log "Installing sysroot..."
    python3 "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_host_arch"

    # Symlink system node so the build system can find it
    mkdir -p "${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    ln -sf "$(which node)" "${_src_dir}/third_party/node/linux/node-linux-x64/bin/node"
}

# ── compile ───────────────────────────────────────────────────────────────────

run_build() {
    log "Compiling chrome + chromedriver..."
    cd "${_src_dir}"
    # Using 'autoninja' is recommended as it detects CPU cores automatically
    if command -v autoninja >/dev/null 2>&1; then
        autoninja -C out/Default chrome chromedriver
    else
        ninja -C out/Default chrome chromedriver
    fi
}

# ── stamp helpers ─────────────────────────────────────────────────────────────

stamp_exists() { [ -f "${_src_dir}/${1}.stamp" ]; }
write_stamp()  { touch "${_src_dir}/${1}.stamp"; }
clear_stamp()  { rm -f "${_src_dir}/${1}.stamp"; }

clear_all_stamps() {
    rm -f "${_src_dir}/"*.stamp
    log "All stamps cleared."
}
