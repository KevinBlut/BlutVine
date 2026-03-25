#!/bin/bash
# shared.sh - Base functions for Project Bifrost
set -euo pipefail

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

repo_root() {
    [ -n "${CHROME_ROOT:-}" ] && echo "$CHROME_ROOT" || echo "${HOME}/Chrome"
}

setup_paths() {
    _root="$(repo_root)"
    _build_dir="${_root}/build"
    _src_dir="${_build_dir}/src"
    _out_dir="${_src_dir}/out/Default"
    _depot_tools_dir="${_build_dir}/depot_tools"

    # Setup Architecture
    _host_arch=$(uname -m)
    case "$_host_arch" in
        x86_64)  _host_arch="x64"  ;;
        aarch64) _host_arch="arm64" ;;
    esac
    _build_arch="${ARCH:-$_host_arch}"
    [ "$_build_arch" = "x86_64" ] && _build_arch="x64"

    mkdir -p "${_build_dir}"
    # Critical: Ensure depot_tools is in PATH for all sub-shells
    export PATH="${_depot_tools_dir}:${PATH}"
}

ensure_depot_tools() {
    if [ ! -d "${_depot_tools_dir}/.git" ]; then
        log "Cloning depot_tools..."
        git clone --depth=1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "${_depot_tools_dir}"
    fi
    export DEPOT_TOOLS_UPDATE=0
}

setup_toolchain() {
    log "Setting up toolchain (Clang, Rust, Sysroot)..."
    python3 "${_src_dir}/tools/rust/update_rust.py"
    python3 "${_src_dir}/tools/clang/scripts/update.py"
    python3 "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_host_arch"

    # Fix: Robust Node.js detection for Debian-based systems
    local node_bin
    node_bin=$(command -v node || command -v nodejs)
    mkdir -p "${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    ln -sf "$node_bin" "${_src_dir}/third_party/node/linux/node-linux-x64/bin/node"
}

stamp_exists() { [ -f "${_src_dir}/${1}.stamp" ]; }
write_stamp()  { touch "${_src_dir}/${1}.stamp"; }
