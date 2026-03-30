#!/bin/bash
set -euo pipefail

# shared build functions — uses depot_tools/gclient, the official Chromium way

repo_root() {
    local base
    base="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    cd "${base}/../.." >/dev/null 2>&1 && pwd
}

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

setup_paths() {
    _root="$(repo_root)"
    _chrome_dir="${_root}/Chrome"
    _patches_dir="${_root}/BlutVine"
    _scripts_dir="${_patches_dir}/scripts"
    _src_dir="${_chrome_dir}/src"
    _out_dir="${_src_dir}/out/Default"
    _depot_tools_dir="${_root}/depot_tools"

    setup_arch
    mkdir -p "${_chrome_dir}"

    local sccache_cfg="${_scripts_dir}/sccache.sh"
    if [ -f "${sccache_cfg}" ]; then
        . "${sccache_cfg}"
    fi
}

# ---------------------------------------------------------------------------
# setup_depot_tools
# ---------------------------------------------------------------------------
setup_depot_tools() {
    if [ ! -d "${_depot_tools_dir}" ]; then
        echo "Cloning depot_tools..."
        git clone --depth=1 \
            https://chromium.googlesource.com/chromium/tools/depot_tools.git \
            "${_depot_tools_dir}"
    else
        echo "depot_tools already present, updating..."
        git -C "${_depot_tools_dir}" pull --ff-only || true
    fi

    export PATH="${_depot_tools_dir}:${PATH}"
    export DEPOT_TOOLS_UPDATE=0
}

# ---------------------------------------------------------------------------
# fetch_chromium
# ---------------------------------------------------------------------------
fetch_chromium() {
    local stamp="${_src_dir}/.downloaded.stamp"

    if [ -f "${stamp}" ]; then
        echo "Chromium sources already present, skipping fetch"
        return 0
    fi

    rm -rf "${_src_dir}" "${_chrome_dir}/.gclient" "${_chrome_dir}/.gclient_entries"
    mkdir -p "${_chrome_dir}"

    echo "Querying latest stable Chromium version..."
    local version
    version=$(curl -fsSL \
        "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=1" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['version'])")
    echo "Latest stable Chromium: ${version}"

    cat > "${_chrome_dir}/.gclient" <<GCLIENT
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

    echo "Cloning Chromium ${version} (no history)..."
    cd "${_chrome_dir}"
    gclient sync --nohooks --no-history

    echo "Installing Chromium system build dependencies..."
    sudo "${_src_dir}/build/install-build-deps.sh" --no-prompt

    echo "Running gclient runhooks (downloads prebuilt toolchain)..."
    cd "${_chrome_dir}"
    gclient runhooks

    # ✅ FIX: Ensure Python toolchain exists (prevents python3_bin_reldir.txt error)
    echo "Ensuring python3 toolchain exists..."
    if [ ! -f "${_src_dir}/buildtools/python3/python3_bin_reldir.txt" ]; then
        echo "Python toolchain missing — retrying gclient runhooks..."
        gclient runhooks
    fi

    if [ ! -f "${_src_dir}/buildtools/python3/python3_bin_reldir.txt" ]; then
        echo "ERROR: python3 toolchain still missing after retry!" >&2
        exit 1
    fi

    echo "Python toolchain verified."

    touch "${stamp}"
}

# ---------------------------------------------------------------------------
# apply_blutvine_patches
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

    echo "Applying BlutVine patches..."
    local patch_file
    while IFS= read -r patch_file || [ -n "${patch_file}" ]; do
        [[ -z "${patch_file}" || "${patch_file}" =~ ^[[:space:]]*# ]] && continue

        local full_path="${_patches_dir}/${patch_file}"
        if [ ! -f "${full_path}" ]; then
            echo "ERROR: patch not found: ${full_path}" >&2
            exit 1
        fi

        echo "  applying ${patch_file}"
        patch -Np1 -d "${_src_dir}" < "${full_path}"
    done < "${series}"

    touch "${stamp}"
    echo "All patches applied."
}

# ---------------------------------------------------------------------------
# write_gn_args
# ---------------------------------------------------------------------------
write_gn_args() {
    mkdir -p "${_out_dir}"

    grep -v "custom_toolchain\|host_toolchain" \
        "${_patches_dir}/flags.linux.gn" > "${_out_dir}/args.gn"

    echo "" >> "${_out_dir}/args.gn"
    echo "# --- added by shared.sh ---" >> "${_out_dir}/args.gn"
    echo "target_cpu = \"${_build_arch}\"" >> "${_out_dir}/args.gn"
    echo "v8_target_cpu = \"${_build_arch}\"" >> "${_out_dir}/args.gn"

    echo "args.gn written."
}

# ---------------------------------------------------------------------------
# setup_sccache
# ---------------------------------------------------------------------------
setup_sccache() {
    if [ -z "${SCCACHE_BUCKET:-}" ]; then
        echo "sccache not configured, skipping"
        return 0
    fi

    local sccache_bin_dir="${HOME}/.local/bin"
    mkdir -p "${sccache_bin_dir}"
    export PATH="${sccache_bin_dir}:${PATH}"

    if ! command -v sccache &>/dev/null; then
        echo "Installing sccache..."
        local triple
        case "${_host_arch}" in
            x64)   triple="x86_64-unknown-linux-musl"  ;;
            arm64) triple="aarch64-unknown-linux-musl" ;;
            *)     triple="x86_64-unknown-linux-musl"  ;;
        esac
        local ver
        ver=$(curl -fsSL https://api.github.com/repos/mozilla/sccache/releases/latest \
            | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
        curl -fsSL \
            "https://github.com/mozilla/sccache/releases/download/${ver}/sccache-${ver}-${triple}.tar.gz" \
            | tar -xz -C "${sccache_bin_dir}" --strip-components=1 \
                "sccache-${ver}-${triple}/sccache"
        chmod +x "${sccache_bin_dir}/sccache"
    fi

    local cache_dir="${_chrome_dir}/.sccache"
    mkdir -p "${cache_dir}"
    export SCCACHE_DIR="${cache_dir}"

    sccache --stop-server 2>/dev/null || true
    export SCCACHE_BUCKET SCCACHE_ENDPOINT SCCACHE_S3_USE_SSL \
           AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    export SCCACHE_MAX_FRAME_LENGTH=104857600
    sccache --start-server
    sleep 1
    sccache --show-stats || true

    echo "cc_wrapper = \"sccache\"" >> "${_out_dir}/args.gn"
}

# ---------------------------------------------------------------------------
# gn_gen
# ---------------------------------------------------------------------------
gn_gen() {
    cd "${_src_dir}"
    echo "Running gn gen..."
    buildtools/linux64/gn gen out/Default --fail-on-unused-args
}

# ---------------------------------------------------------------------------
# maybe_build
# ---------------------------------------------------------------------------
maybe_build() {
    if [ -n "${_prepare_only:-}" ]; then
        echo "_prepare_only set — skipping build"
        return 0
    fi
    cd "${_src_dir}"
    echo "Building chrome and chromedriver..."
    autoninja -C out/Default chrome chromedriver
}
