#!/bin/bash
# shared.sh
# Base functions for Project Bifrost
set -euo pipefail

log()  { echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── repo root ─────────────────────────────────────────────────────────────────

repo_root() {
    # If CHROME_ROOT is exported by setup.sh, use it as the source of truth.
    if [ -n "${CHROME_ROOT:-}" ]; then
        echo "$CHROME_ROOT"
        return
    fi
    local _base
    _base="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    cd "${_base}/.." >/dev/null 2>&1 && pwd
}

# ── architecture & paths ──────────────────────────────────────────────────────

setup_paths() {
    _root="$(repo_root)"
    _build_dir="${_root}/build"
    _src_dir="${_build_dir}/src"
    _out_dir="${_src_dir}/out/Default"
    _depot_tools_dir="${_build_dir}/depot_tools"

    _host_arch=$(uname -m)
    case "$_host_arch" in
        x86_64)  _host_arch="x64"  ;;
        aarch64) _host_arch="arm64" ;;
    esac
    _build_arch="${ARCH:-$_host_arch}"
    [ "$_build_arch" = "x86_64" ] && _build_arch="x64"

    mkdir -p "${_build_dir}"
    # Ensure depot_tools is at the front of the PATH
    export PATH="${_depot_tools_dir}:${PATH}"
}

# ── toolchain & depot_tools ───────────────────────────────────────────────────

ensure_depot_tools() {
    if [ ! -d "${_depot_tools_dir}/.git" ]; then
        log "Cloning depot_tools..."
        git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "${_depot_tools_dir}"
    else
        log "Updating depot_tools..."
        # This helps prevent the 'python3_bin_reldir.txt' missing error
        (cd "${_depot_tools_dir}" && ./update_depot_tools) || true
    fi
    # Prevent depot_tools from auto-updating during every single command
    export DEPOT_TOOLS_UPDATE=0
}

setup_toolchain() {
    log "Setting up toolchain (Clang, Rust, Sysroot)..."
    python3 "${_src_dir}/tools/rust/update_rust.py"
    python3 "${_src_dir}/tools/clang/scripts/update.py"
    python3 "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_host_arch"

    # Fix: Robust Node.js detection for Debian/Ubuntu
    local node_bin
    node_bin=$(command -v node || command -v nodejs)
    mkdir -p "${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    ln -sf "$node_bin" "${_src_dir}/third_party/node/linux/node-linux-x64/bin/node"
}

# ── gn generate ───────────────────────────────────────────────────────────────

gn_gen() {
    log "Generating build files with gn..."
    
    # Critical Fix: Ensure depot_tools is bootstrapped so gn finds its python helpers
    if [ -d "${_depot_tools_dir}" ]; then
        bash "${_depot_tools_dir}/update_depot_tools" || true
    fi

    cd "${_src_dir}"
    # Call gn explicitly from depot_tools to avoid path conflicts
    "${_depot_tools_dir}/gn" gen out/Default
}

# ── stamp helpers ─────────────────────────────────────────────────────────────

stamp_exists() { [ -f "${_src_dir}/${1}.stamp" ]; }
write_stamp()  { touch "${_src_dir}/${1}.stamp"; }
