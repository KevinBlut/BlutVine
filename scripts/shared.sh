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

    _build_dir="${_root}/build"
    _src_dir="${_build_dir}/src"
    _out_dir="${_src_dir}/out/Default"

    _dl_cache="${_build_dir}/download_cache"
    _depot_tools_dir="${_build_dir}/depot_tools"

    # BlutVine root — overridable via env var.
    # series file lives at: ${_blutvine_dir}/series
    # patches live at:      ${_blutvine_dir}/fingerprint-chromium/
    _blutvine_dir="${BLUTVINE_DIR:-${HOME}/BlutVine}"

    setup_arch
    mkdir -p "${_dl_cache}" "${_build_dir}"
}

# ── chromium version ──────────────────────────────────────────────────────────

# Hits the Chromium releases API, caches the result to chromium_version.txt.
# Called only from fetch.sh — no other script should call this.
fetch_and_cache_version() {
    log "Fetching latest stable Chromium version..."
    local api_url="https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=1"
    local version
    version=$(curl -fsSL "$api_url" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data[0]['version'])
" 2>/dev/null) || die "Failed to fetch latest stable Chromium version from API"
    log "Latest stable: ${version}"
    echo "$version" > "${_build_dir}/chromium_version.txt"
}

# Reads the version that fetch.sh already cached to disk.
# Safe to call once the gclient_synced stamp exists — fetch.sh writes both.
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
    # Do NOT set DEPOT_TOOLS_UPDATE=0 globally — depot_tools needs to be able
    # to bootstrap itself (writes python3_bin_reldir.txt, etc.) on first use.
    export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1
}

# ── toolchain ─────────────────────────────────────────────────────────────────

setup_toolchain() {
    log "Setting up toolchain (clang + rust + sysroot)..."

    if [ "$_host_arch" = x64 ]; then
        log "Downloading prebuilt Clang and Rust..."
        python3 "${_src_dir}/tools/rust/update_rust.py"
        python3 "${_src_dir}/tools/clang/scripts/update.py"
    else
        log "Non-x64 host detected. Building toolchain from source..."
        python3 "${_src_dir}/tools/clang/scripts/build.py" --without-fuchsia --without-android
    fi

    log "Installing sysroot..."
    python3 "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_host_arch"

    mkdir -p "${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    ln -sf "$(which node)" "${_src_dir}/third_party/node/linux/node-linux-x64/bin/node"
}

# ── gn generate ───────────────────────────────────────────────────────────────

gn_gen() {
    log "Bootstrapping depot_tools before gn gen..."
    # Scoped subshell so DEPOT_TOOLS_UPDATE=1 only applies here.
    # Ensures python3_bin_reldir.txt is written before gn is invoked.
    (
        export DEPOT_TOOLS_UPDATE=1
        if [ -f "${_depot_tools_dir}/ensure_bootstrap" ]; then
            "${_depot_tools_dir}/ensure_bootstrap"
        else
            "${_depot_tools_dir}/gclient" --version >/dev/null 2>&1 || true
        fi
    )

    log "Generating build files with gn..."
    cd "${_src_dir}"
    "${_depot_tools_dir}/gn" gen out/Default
    log "gn gen complete."
}

# ── compile ───────────────────────────────────────────────────────────────────

run_build() {
    log "Compiling chrome + chromedriver..."
    cd "${_src_dir}"
    if [ -f "${_depot_tools_dir}/autoninja" ]; then
        "${_depot_tools_dir}/autoninja" -C out/Default chrome chromedriver
    elif command -v autoninja >/dev/null 2>&1; then
        autoninja -C out/Default chrome chromedriver
    elif command -v ninja >/dev/null 2>&1; then
        ninja -C out/Default chrome chromedriver
    else
        die "No build tool found. Install ninja-build: sudo apt install ninja-build"
    fi
}

# ── stamp helpers ─────────────────────────────────────────────────────────────

# All stamp functions require setup_paths() to have been called first.

stamp_exists() { [ -f "${_src_dir}/${1}.stamp" ]; }
write_stamp()  { touch "${_src_dir}/${1}.stamp"; }
clear_stamp()  { rm -f "${_src_dir}/${1}.stamp"; }

clear_all_stamps() {
    find "${_src_dir}" -maxdepth 1 -name "*.stamp" -delete
    log "All stamps cleared."
}
