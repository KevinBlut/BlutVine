#!/bin/bash
# shared.sh — shared build functions
# Based directly on ungoogled-chromium/scripts/shared.sh
# Differences from reference:
#   - fetch_sources() uses gclient to pull latest stable vanilla Chromium
#     instead of ungoogled's downloads.py / clone.py
#   - apply_patches() reads ~/BlutVine/fingerprint-chromium/series
#     instead of ungoogled's patches.py utility
#   - no prune_binaries / domain_substitution (vanilla Chromium, not needed)
set -euo pipefail

repo_root() {
    local _base_dir
    _base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    cd "${_base_dir}/.." >/dev/null 2>&1 && pwd
}

setup_arch() {
    _host_arch=$(uname -m)

    if [ "$_host_arch" = "x86_64" ]; then
        _host_arch="x64"
    elif [ "$_host_arch" = "aarch64" ]; then
        _host_arch="arm64"
    fi

    _build_arch="$_host_arch"
    if [ -n "${ARCH:-}" ]; then
        _build_arch="$ARCH"
    fi

    if [ "$_build_arch" = "x86_64" ]; then
        _build_arch=x64
    fi
}

setup_paths() {
    _root="${HOME}/Chrome"
    _build_dir="${_root}/build"
    _dl_cache="${_build_dir}/download_cache"
    _depot_tools_dir="${_build_dir}/depot_tools"
    _src_dir="${_build_dir}/src"
    _out_dir="${_src_dir}/out/Default"
    _blutvine_patches="${HOME}/BlutVine/fingerprint-chromium"
    setup_arch

    mkdir -p "${_dl_cache}"
}

fetch_sources() {
    local stamp="${_src_dir}/.downloaded.stamp"

    if [ -f "${stamp}" ]; then
        echo "Sources already present, skipping download/unpack"
        return 0
    fi

    # Fetch latest stable version from Chromium dash
    local version
    version=$(curl -fsSL \
        "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=1" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['version'])") \
        || { echo "ERROR: failed to fetch latest stable version" >&2; exit 1; }
    echo "Latest stable Chromium: ${version}"
    echo "${version}" > "${_build_dir}/chromium_version.txt"

    # Ensure depot_tools
    if [ ! -d "${_depot_tools_dir}/.git" ]; then
        echo "Cloning depot_tools..."
        git clone --depth=1 \
            https://chromium.googlesource.com/chromium/tools/depot_tools.git \
            "${_depot_tools_dir}"
    fi
    export PATH="${_depot_tools_dir}:${PATH}"
    export DEPOT_TOOLS_UPDATE=0
    export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1

    # Write .gclient pinned to the stable tag
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

    [ -f "${_src_dir}/BUILD.gn" ] || \
        { echo "ERROR: source tree looks incomplete — BUILD.gn missing" >&2; exit 1; }

    touch "${stamp}"
}

apply_patches() {
    if [ ! -f "${_src_dir}/.patched.stamp" ]; then
        local series="${_blutvine_patches}/series"
        [ -f "${series}" ] || \
            { echo "ERROR: series file not found: ${series}" >&2; exit 1; }

        echo "Applying patches from: ${series}"
        cd "${_src_dir}"

        while IFS= read -r patch || [ -n "${patch}" ]; do
            [[ -z "${patch}" || "${patch}" == \#* ]] && continue
            local patch_path="${_blutvine_patches}/${patch}"
            [ -f "${patch_path}" ] || \
                { echo "ERROR: patch not found: ${patch_path}" >&2; exit 1; }
            echo "  -> ${patch}"
            git apply --ignore-whitespace --ignore-space-change "${patch_path}" || \
                { echo "ERROR: failed to apply ${patch}" >&2; exit 1; }
        done < "${series}"

        touch "${_src_dir}/.patched.stamp"
    fi
}

write_gn_args() {
    mkdir -p "${_out_dir}"

    if [ -f "${_root}/flags.linux.gn" ]; then
        cat "${_root}/flags.linux.gn" | tee "${_out_dir}/args.gn"
    else
        cat > "${_out_dir}/args.gn" <<'GN'
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
use_cups = true
use_pulseaudio = true
link_pulseaudio = true
GN
    fi

    echo "target_cpu = \"${_build_arch}\""    | tee -a "${_out_dir}/args.gn"
    echo "v8_target_cpu = \"${_build_arch}\"" | tee -a "${_out_dir}/args.gn"
}

fix_tool_downloading() {
    sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' \
        "${_src_dir}/build/linux/sysroot_scripts/sysroots.json" \
        "${_src_dir}/tools/clang/scripts/update.py" \
        "${_src_dir}/tools/clang/scripts/build.py" 2>/dev/null || true

    sed -i 's/chromium.9oo91esource.qjz9zk/chromium.googlesource.com/g' \
        "${_src_dir}/tools/clang/scripts/build.py" \
        "${_src_dir}/tools/rust/build_rust.py" \
        "${_src_dir}/tools/rust/build_bindgen.py" 2>/dev/null || true

    sed -i 's/chrome-infra-packages.8pp2p8t.qjz9zk/chrome-infra-packages.appspot.com/g' \
        "${_src_dir}/tools/rust/build_rust.py" 2>/dev/null || true
}

setup_toolchain() {
    if [ "$_host_arch" = x64 ]; then
        "${_src_dir}/tools/rust/update_rust.py"
        "${_src_dir}/tools/clang/scripts/update.py"
    else
        "${_src_dir}/tools/clang/scripts/build.py" \
            --without-fuchsia --without-android --disable-asserts \
            --host-cc=clang --host-cxx=clang++ --use-system-cmake \
            --with-ml-inliner-model=

        export CARGO_HOME="${_src_dir}/third_party/rust-src/cargo-home"
        "${_src_dir}/tools/rust/build_rust.py" \
            --skip-test

        "${_src_dir}/tools/rust/build_bindgen.py"
    fi

    if grep -q -F "use_sysroot=true" "${_out_dir}/args.gn"; then
        "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_host_arch" &
        if [ "$_build_arch" != "$_host_arch" ]; then
            "${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py" --arch="$_build_arch" &
        fi
        wait
    fi

    local _node_bin
    _node_bin="$(which node 2>/dev/null)" \
        || { echo "ERROR: node not found. Install with: sudo apt install nodejs" >&2; exit 1; }
    mkdir -p "${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    ln -sf "${_node_bin}" "${_src_dir}/third_party/node/linux/node-linux-x64/bin/node"

    local clang_bin="${_src_dir}/third_party/llvm-build/Release+Asserts/bin"
    export CC="${clang_bin}/clang"
    export CXX="${clang_bin}/clang++"
    export AR="${clang_bin}/llvm-ar"
    export NM="${clang_bin}/llvm-nm"
    export LLVM_BIN="${clang_bin}"

    local resource_dir
    resource_dir="$(${CC%% *} --print-resource-dir)"
    export CXXFLAGS+=" -resource-dir=${resource_dir} -B${LLVM_BIN}"
    export CPPFLAGS+=" -resource-dir=${resource_dir} -B${LLVM_BIN}"
    export CFLAGS+=" -resource-dir=${resource_dir} -B${LLVM_BIN}"
}

gn_gen() {
    cd "${_src_dir}"
    ./tools/gn/bootstrap/bootstrap.py -o out/Default/gn --skip-generate-buildfiles
    ./out/Default/gn gen out/Default --fail-on-unused-args
}

maybe_build() {
    cd "${_src_dir}"
    ninja -C out/Default chrome chromedriver
}
