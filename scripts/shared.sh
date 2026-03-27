#!/bin/bash
set -euo pipefail

# shared build functions used by local and CI scripts

# resolve repo root directory regardless of caller location
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
    _root="$(repo_root)"
    _scripts_dir="${_root}/scripts"
    _chrome_dir="${_root}/Chrome"              # vanilla Chromium sources live here
    _patches_dir="${_root}/BlutVine"           # your patch series lives here
    _build_dir="${_chrome_dir}/build"          # build artefacts stay inside Chrome/build/
    _dl_cache="${_chrome_dir}/download_cache"  # tarball cache inside Chrome/
    _src_dir="${_build_dir}/src"               # Chrome/build/src
    _out_dir="${_src_dir}/out/Default"
    setup_arch

    mkdir -p "${_chrome_dir}" "${_dl_cache}" "${_build_dir}"

    # load sccache credentials if the config file exists
    local sccache_cfg="${_scripts_dir}/sccache.sh"
    if [ -f "${sccache_cfg}" ]; then
        # shellcheck source=/dev/null
        . "${sccache_cfg}"
    fi
}

# ---------------------------------------------------------------------------
# setup_sccache
#   Installs sccache if missing, verifies the B2 connection, and sets the
#   compiler wrapper env vars that Chromium's build system will pick up.
# ---------------------------------------------------------------------------
setup_sccache() {
    if [ -z "${SCCACHE_BUCKET:-}" ]; then
        echo "sccache not configured (SCCACHE_BUCKET not set), skipping"
        return 0
    fi

    # install sccache if not already present
    if ! command -v sccache &>/dev/null; then
        echo "Installing sccache..."
        if command -v cargo &>/dev/null; then
            cargo install sccache
        else
            # grab the latest prebuilt binary from GitHub releases
            local sccache_ver
            sccache_ver=$(curl -fsSL \
                "https://api.github.com/repos/mozilla/sccache/releases/latest" \
                | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
            local sccache_url="https://github.com/mozilla/sccache/releases/download/${sccache_ver}/sccache-${sccache_ver}-x86_64-unknown-linux-musl.tar.gz"
            curl -fsSL "${sccache_url}" \
                | tar -xz -C /usr/local/bin --strip-components=1 \
                    "sccache-${sccache_ver}-x86_64-unknown-linux-musl/sccache"
            chmod +x /usr/local/bin/sccache
        fi
    fi

    # stop any existing sccache server so we start fresh with B2 config
    sccache --stop-server 2>/dev/null || true

    # these vars tell sccache to use B2 as its storage backend.
    # they must be exported before --start-server so the server
    # process inherits them and knows where to save/fetch cache entries.
    export SCCACHE_BUCKET="${SCCACHE_BUCKET}"
    export SCCACHE_ENDPOINT="${SCCACHE_ENDPOINT}"
    export SCCACHE_S3_USE_SSL="${SCCACHE_S3_USE_SSL:-true}"
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
    export SCCACHE_MAX_FRAME_LENGTH=104857600

    echo "Starting sccache server with Backblaze B2 backend..."
    sccache --start-server

    echo "sccache version: $(sccache --version)"
    echo "sccache stats (should show B2 as backend):"
    sccache --show-stats

    # tell Chromium's build to use sccache as the compiler wrapper
    export CC_wrapper="sccache"
    export CXX_wrapper="sccache"
}

# ---------------------------------------------------------------------------
# fetch_chromium
#   Queries the Chrome release API for the latest stable version, then
#   downloads and unpacks the official Chromium source tarball from the
#   Google Storage bucket.  A stamp file prevents re-downloading.
# ---------------------------------------------------------------------------
fetch_chromium() {
    local stamp="${_src_dir}/.downloaded.stamp"

    if [ -f "${stamp}" ]; then
        echo "Chromium sources already present, skipping download/unpack"
        return 0
    fi

    echo "Querying latest stable Chromium version..."

    # ChromiumDash returns a JSON array; grab the first element's version field.
    local version
    version=$(curl -fsSL \
        "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=1" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['version'])")

    echo "Latest stable Chromium: ${version}"

    local tarball="chromium-${version}.tar.xz"
    local url="https://commondatastorage.googleapis.com/chromium-browser-official/${tarball}"
    local dest="${_dl_cache}/${tarball}"

    if [ ! -f "${dest}" ]; then
        echo "Downloading ${url} ..."
        curl -fL --retry 5 --retry-delay 10 -o "${dest}" "${url}"
    else
        echo "Tarball already cached at ${dest}"
    fi

    echo "Unpacking ${tarball} into ${_chrome_dir} ..."
    mkdir -p "${_chrome_dir}"
    tar -xf "${dest}" -C "${_chrome_dir}" --strip-components=1

    touch "${stamp}"
}

# ---------------------------------------------------------------------------
# apply_blutvine_patches
#   Reads BlutVine/series (one patch filename per line, '#' lines ignored)
#   and applies each patch to the source tree with `patch -p1`.
#   A stamp file prevents re-applying on subsequent runs.
# ---------------------------------------------------------------------------
apply_blutvine_patches() {
    local stamp="${_src_dir}/.patched.stamp"

    if [ -f "${stamp}" ]; then
        echo "Patches already applied, skipping"
        return 0
    fi

    local series="${_root}/series"
    if [ ! -f "${series}" ]; then
        echo "ERROR: patch series file not found at ${series}" >&2
        exit 1
    fi

    echo "Applying BlutVine patches from ${series} ..."

    local patch_file
    while IFS= read -r patch_file || [ -n "${patch_file}" ]; do
        # skip blank lines and comments
        [[ -z "${patch_file}" || "${patch_file}" =~ ^[[:space:]]*# ]] && continue

        local full_path="${_patches_dir}/${patch_file}"
        if [ ! -f "${full_path}" ]; then
            echo "ERROR: patch not found: ${full_path}" >&2
            exit 1
        fi

        echo "  applying ${patch_file}"
        patch -p1 -d "${_src_dir}" < "${full_path}"
    done < "${series}"

    touch "${stamp}"
    echo "All BlutVine patches applied successfully."
}

write_gn_args() {
    mkdir -p "${_out_dir}"

    # Use only your own flags file; ungoogled-chromium flags.gn is gone.
    cat "${_root}/flags.linux.gn" | tee "${_out_dir}/args.gn"
    echo "target_cpu = \"$_build_arch\"" | tee -a "${_out_dir}/args.gn"
    echo "v8_target_cpu = \"$_build_arch\"" | tee -a "${_out_dir}/args.gn"
}

# fix downloading of prebuilt tools and sysroot files
# (https://github.com/ungoogled-software/ungoogled-chromium/issues/1846)
fix_tool_downloading() {
    sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' \
        "${_src_dir}/build/linux/sysroot_scripts/sysroots.json" \
        "${_src_dir}/tools/clang/scripts/update.py" \
        "${_src_dir}/tools/clang/scripts/build.py"

    sed -i 's/chromium.9oo91esource.qjz9zk/chromium.googlesource.com/g' \
        "${_src_dir}/tools/clang/scripts/build.py" \
        "${_src_dir}/tools/rust/build_rust.py" \
        "${_src_dir}/tools/rust/build_bindgen.py"

    sed -i 's/chrome-infra-packages.8pp2p8t.qjz9zk/chrome-infra-packages.appspot.com/g' \
        "${_src_dir}/tools/rust/build_rust.py"
}

setup_toolchain() {
    # Chromium currently has no non-x86 llvm/rust builds on
    # Linux, so we have to build it ourselves.
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

    mkdir -p "${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    ln -sf "$(which node)" "${_src_dir}/third_party/node/linux/node-linux-x64/bin/node"

    local clang_bin="${_src_dir}/third_party/llvm-build/Release+Asserts/bin"
    # wrap clang with sccache if it was configured
    if [ -n "${CC_wrapper:-}" ]; then
        export CC="${CC_wrapper} ${clang_bin}/clang"
        export CXX="${CXX_wrapper} ${clang_bin}/clang++"
    else
        export CC="${clang_bin}/clang"
        export CXX="${clang_bin}/clang++"
    fi
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
