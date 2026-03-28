#!/bin/bash
set -euo pipefail

# shared build functions used by local and CI scripts

# ---------------------------------------------------------------------------
# repo_root
#   Resolves the parent directory that contains both BlutVine/ and Chrome/
# ---------------------------------------------------------------------------
repo_root() {
    local _base_dir
    _base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    # BASH_SOURCE[0] is BlutVine/scripts/shared.sh
    # ..    = BlutVine/
    # ../.. = repo root (where Chrome/ lives alongside BlutVine/)
    cd "${_base_dir}/../.." >/dev/null 2>&1 && pwd
}

# ---------------------------------------------------------------------------
# setup_arch
#   Sets _host_arch and _build_arch (both use GN-style names: x64 / arm64)
# ---------------------------------------------------------------------------
setup_arch() {
    _host_arch=$(uname -m)
    case "${_host_arch}" in
        x86_64)  _host_arch="x64"   ;;
        aarch64) _host_arch="arm64" ;;
    esac

    _build_arch="${_host_arch}"
    if [ -n "${ARCH:-}" ]; then
        _build_arch="${ARCH}"
        [ "${_build_arch}" = "x86_64" ] && _build_arch="x64"
    fi
}

# ---------------------------------------------------------------------------
# setup_paths
#   Initialises all path variables and sources sccache credentials if present
# ---------------------------------------------------------------------------
setup_paths() {
    _root="$(repo_root)"
    _chrome_dir="${_root}/Chrome"
    _patches_dir="${_root}/BlutVine"
    _scripts_dir="${_patches_dir}/scripts"
    _build_dir="${_chrome_dir}/build"
    _dl_cache="${_chrome_dir}/download_cache"
    _src_dir="${_build_dir}/src"
    _out_dir="${_src_dir}/out/Default"

    setup_arch

    mkdir -p "${_chrome_dir}" "${_dl_cache}" "${_build_dir}"

    local sccache_cfg="${_scripts_dir}/sccache.sh"
    if [ -f "${sccache_cfg}" ]; then
        # shellcheck source=/dev/null
        . "${sccache_cfg}"
    fi
}

# ---------------------------------------------------------------------------
# check_system_deps
#   Verifies that required system tools are present before we start.
#   The tarball ships NO toolchain — we rely entirely on the system.
# ---------------------------------------------------------------------------
check_system_deps() {
    local missing=()

    # clang is mandatory — gcc is NOT supported by Chromium's build system
    if ! command -v clang &>/dev/null; then
        missing+=("clang (install: apt-get install clang)")
    fi
    if ! command -v clang++ &>/dev/null; then
        missing+=("clang++ (install: apt-get install clang)")
    fi

    # lld is the only supported linker for Chromium
    if ! command -v ld.lld &>/dev/null; then
        missing+=("lld (install: apt-get install lld)")
    fi

    # ninja for the actual build
    if ! command -v ninja &>/dev/null && ! command -v ninja-build &>/dev/null; then
        missing+=("ninja (install: apt-get install ninja-build)")
    fi

    # python3 for GN scripts
    if ! command -v python3 &>/dev/null; then
        missing+=("python3 (install: apt-get install python3)")
    fi

    # node for JS build steps
    if ! command -v node &>/dev/null && ! command -v nodejs &>/dev/null; then
        missing+=("nodejs (install: apt-get install nodejs)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: missing required build dependencies:" >&2
        for dep in "${missing[@]}"; do
            echo "  - ${dep}" >&2
        done
        echo "" >&2
        echo "On Debian/Ubuntu you can install everything with:" >&2
        echo "  sudo apt-get install clang lld ninja-build python3 nodejs" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# setup_sccache
#   Installs sccache if SCCACHE_BUCKET is configured, starts the server,
#   and sets CC_wrapper / CXX_wrapper for use later in setup_toolchain.
# ---------------------------------------------------------------------------
setup_sccache() {
    if [ -z "${SCCACHE_BUCKET:-}" ]; then
        echo "sccache not configured (SCCACHE_BUCKET not set), skipping"
        return 0
    fi

    local sccache_bin_dir="${HOME}/.local/bin"
    local sccache_bin="${sccache_bin_dir}/sccache"
    mkdir -p "${sccache_bin_dir}"
    export PATH="${sccache_bin_dir}:${PATH}"

    if ! command -v sccache &>/dev/null; then
        echo "Installing sccache..."
        if command -v cargo &>/dev/null; then
            cargo install sccache --root "${HOME}/.local"
        else
            local sccache_triple
            case "${_host_arch}" in
                x64)   sccache_triple="x86_64-unknown-linux-musl"  ;;
                arm64) sccache_triple="aarch64-unknown-linux-musl" ;;
                *)     sccache_triple="x86_64-unknown-linux-musl"  ;;
            esac

            local sccache_ver
            sccache_ver=$(curl -fsSL \
                "https://api.github.com/repos/mozilla/sccache/releases/latest" \
                | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")

            echo "Downloading sccache ${sccache_ver} (${sccache_triple})..."
            curl -fsSL \
                "https://github.com/mozilla/sccache/releases/download/${sccache_ver}/sccache-${sccache_ver}-${sccache_triple}.tar.gz" \
                | tar -xz -C "${sccache_bin_dir}" --strip-components=1 \
                    "sccache-${sccache_ver}-${sccache_triple}/sccache"
            chmod +x "${sccache_bin}"
        fi
    fi

    local sccache_cache_dir="${_chrome_dir}/.sccache"
    mkdir -p "${sccache_cache_dir}"
    export SCCACHE_DIR="${sccache_cache_dir}"

    sccache --stop-server 2>/dev/null || true

    export SCCACHE_BUCKET="${SCCACHE_BUCKET}"
    export SCCACHE_ENDPOINT="${SCCACHE_ENDPOINT}"
    export SCCACHE_S3_USE_SSL="${SCCACHE_S3_USE_SSL:-true}"
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
    export SCCACHE_MAX_FRAME_LENGTH=104857600

    echo "Starting sccache server with Backblaze B2 backend..."
    sccache --start-server
    sleep 1

    echo "sccache version: $(sccache --version)"
    sccache --show-stats || echo "Warning: sccache stats unavailable"

    export CC_wrapper="sccache"
    export CXX_wrapper="sccache"
}

# ---------------------------------------------------------------------------
# fetch_chromium
#   Downloads the latest stable Chromium tarball and unpacks it.
#   A stamp file prevents re-downloading on subsequent runs.
# ---------------------------------------------------------------------------
fetch_chromium() {
    local stamp="${_src_dir}/.downloaded.stamp"

    if [ -f "${stamp}" ]; then
        echo "Chromium sources already present, skipping download/unpack"
        return 0
    fi

    echo "Querying latest stable Chromium version..."
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

    echo "Unpacking ${tarball} into ${_src_dir} ..."
    mkdir -p "${_src_dir}"
    tar -xf "${dest}" -C "${_src_dir}" --strip-components=1

    mkdir -p "$(dirname "${stamp}")"
    touch "${stamp}"
}

# ---------------------------------------------------------------------------
# apply_blutvine_patches
#   Applies patches listed in BlutVine/series (one filename per line).
#   Skips blank lines and '#' comments.
# ---------------------------------------------------------------------------
apply_blutvine_patches() {
    local stamp="${_src_dir}/.patched.stamp"

    if [ -f "${stamp}" ]; then
        echo "Patches already applied, skipping"
        return 0
    fi

    local series="${_patches_dir}/series"
    if [ ! -f "${series}" ]; then
        echo "ERROR: patch series file not found at ${series}" >&2
        exit 1
    fi

    echo "Applying BlutVine patches from ${series} ..."

    local patch_file
    while IFS= read -r patch_file || [ -n "${patch_file}" ]; do
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

# ---------------------------------------------------------------------------
# write_gn_args
#   Writes args.gn telling GN to use the system (unbundled) toolchain.
#   This is the key difference from the old approach: instead of trying to
#   download/bootstrap Chromium's own clang+rust, we hand GN our system
#   clang and let it drive the build directly.
# ---------------------------------------------------------------------------
write_gn_args() {
    mkdir -p "${_out_dir}"
    cat "${_patches_dir}/flags.linux.gn" > "${_out_dir}/args.gn"

    # Tell GN to use whatever CC/CXX are set in the environment
    # (the unbundle toolchain reads AR, CC, CXX, NM from the env)
    cat >> "${_out_dir}/args.gn" <<EOF

# --- added by shared.sh ---
target_cpu = "${_build_arch}"
v8_target_cpu = "${_build_arch}"
EOF

    echo "args.gn written to ${_out_dir}/args.gn"
}

# ---------------------------------------------------------------------------
# fix_tool_downloading
#   Restores real Google hostnames that ungoogled-chromium domain-substitutes.
#   Needed so that any remaining download scripts (sysroot, etc.) can reach
#   the actual servers.
# ---------------------------------------------------------------------------
fix_tool_downloading() {
    sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' \
        "${_src_dir}/build/linux/sysroot_scripts/sysroots.json" \
        2>/dev/null || true

    # no-op if the file doesn't exist (vanilla tarball keeps real hostnames)
}

# ---------------------------------------------------------------------------
# install_sysroot
#   Downloads the Debian sysroot matching the target arch.
#   Only needed when use_sysroot=true is in args.gn (it usually is for
#   portable/distro-agnostic builds).  Safe to skip for local builds where
#   you just want to run on the build machine.
# ---------------------------------------------------------------------------
install_sysroot() {
    if ! grep -q "use_sysroot\s*=\s*true" "${_out_dir}/args.gn" 2>/dev/null; then
        echo "use_sysroot not set, skipping sysroot install"
        return 0
    fi

    local install_script="${_src_dir}/build/linux/sysroot_scripts/install-sysroot.py"
    if [ ! -f "${install_script}" ]; then
        echo "WARNING: sysroot install script not found, skipping" >&2
        return 0
    fi

    echo "Installing sysroot for ${_host_arch}..."
    python3 "${install_script}" --arch="${_host_arch}"

    if [ "${_build_arch}" != "${_host_arch}" ]; then
        echo "Installing sysroot for cross-compile target ${_build_arch}..."
        python3 "${install_script}" --arch="${_build_arch}"
    fi
}

# ---------------------------------------------------------------------------
# setup_toolchain
#   Sets CC, CXX, AR, NM to the system clang binaries.
#   Wraps them with sccache if CC_wrapper is set.
#   Also symlinks node into the path Chromium's build scripts expect.
# ---------------------------------------------------------------------------
setup_toolchain() {
    # Resolve clang path — prefer clang from PATH, fail loudly if missing
    local clang_bin
    clang_bin=$(command -v clang)
    local clangxx_bin
    clangxx_bin=$(command -v clang++)

    # Wrap with sccache if configured
    if [ -n "${CC_wrapper:-}" ]; then
        export CC="${CC_wrapper} ${clang_bin}"
        export CXX="${CXX_wrapper} ${clangxx_bin}"
    else
        export CC="${clang_bin}"
        export CXX="${clangxx_bin}"
    fi

    # lld-based tools (llvm-ar / llvm-nm are preferred; fall back to system ar/nm)
    export AR="${AR:-$(command -v llvm-ar 2>/dev/null || command -v ar)}"
    export NM="${NM:-$(command -v llvm-nm 2>/dev/null || command -v nm)}"

    # LLVM_BIN is used by GN's unbundle toolchain to find lld, llvm-ar, etc.
    # Point it at wherever clang lives.
    export LLVM_BIN
    LLVM_BIN="$(dirname "${clang_bin}")"

    # Compiler resource dir — always query raw clang, never the sccache wrapper
    local resource_dir
    resource_dir="$("${clang_bin}" --print-resource-dir)"
    export CFLAGS="${CFLAGS:-}  -resource-dir=${resource_dir}"
    export CXXFLAGS="${CXXFLAGS:-} -resource-dir=${resource_dir}"
    export CPPFLAGS="${CPPFLAGS:-} -resource-dir=${resource_dir}"

    # Symlink node into the location Chromium's build scripts expect
    local node_target_dir="${_src_dir}/third_party/node/linux/node-linux-x64/bin"
    mkdir -p "${node_target_dir}"

    local node_path
    node_path=$(command -v node 2>/dev/null || command -v nodejs 2>/dev/null || true)
    if [ -z "${node_path}" ]; then
        echo "ERROR: node/nodejs not found in PATH" >&2
        exit 1
    fi
    ln -sf "${node_path}" "${node_target_dir}/node"
    echo "Node.js symlinked: ${node_path} -> ${node_target_dir}/node"

    echo "Toolchain:"
    echo "  CC  = ${CC}"
    echo "  CXX = ${CXX}"
    echo "  AR  = ${AR}"
    echo "  NM  = ${NM}"
    echo "  LLVM_BIN = ${LLVM_BIN}"
}

# ---------------------------------------------------------------------------
# gn_gen
#   Bootstraps gn (if not already present) then runs gn gen.
#
#   bootstrap.py compiles gn itself from source using the HOST compiler.
#   We must pass it the raw clang path (never sccache-wrapped) otherwise
#   the internal ninja invocation inside bootstrap.py will fail.
# ---------------------------------------------------------------------------
gn_gen() {
    cd "${_src_dir}"

    local gn_bin="${_out_dir}/gn"

    if [ ! -f "${gn_bin}" ]; then
        echo "Bootstrapping gn..."

        # bootstrap.py builds gn using CC/CXX from the environment.
        # Forcibly use raw clang here — sccache wrapping breaks the bootstrap.
        local raw_clang
        raw_clang=$(command -v clang)
        local raw_clangxx
        raw_clangxx=$(command -v clang++)

        CC="${raw_clang}" CXX="${raw_clangxx}" \
        python3 tools/gn/bootstrap/bootstrap.py \
            --skip-generate-buildfiles \
            -o "${gn_bin}"
    else
        echo "gn already built at ${gn_bin}, skipping bootstrap"
    fi

    echo "Running gn gen..."
    "${gn_bin}" gen out/Default --fail-on-unused-args
}

# ---------------------------------------------------------------------------
# maybe_build
#   Runs ninja to compile chrome and chromedriver.
# ---------------------------------------------------------------------------
maybe_build() {
    if [ -n "${_prepare_only:-}" ]; then
        echo "_prepare_only is set — skipping ninja build"
        return 0
    fi

    cd "${_src_dir}"

    local ninja_bin
    ninja_bin=$(command -v ninja 2>/dev/null || command -v ninja-build 2>/dev/null)

    echo "Building chrome and chromedriver with ninja..."
    "${ninja_bin}" -C out/Default chrome chromedriver
}
