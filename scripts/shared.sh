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

    export PATH="${_depot_tools_dir}:${_depot_tools_dir}/.cipd_bin:${PATH}"

    unset DEPOT_TOOLS_UPDATE

    echo "Downloading CIPD packages..."
    "${_depot_tools_dir}/cipd" ensure \
        -ensure-file "${_depot_tools_dir}/cipd_manifest.txt" \
        -root "${_depot_tools_dir}"

    echo "Bootstrapping depot_tools (Python, CIPD, etc)..."
    "${_depot_tools_dir}/ensure_bootstrap" || true
}

# ---------------------------------------------------------------------------
# fetch_chromium
# ---------------------------------------------------------------------------
fetch_chromium() {
    local stamp="${_src_dir}/.downloaded.stamp"

    if [ -f "${stamp}" ]; then
        echo "Chromium sources already present, skipping fetch."
        return 0
    fi

    echo "Fixing any interrupted dpkg state..."
    sudo dpkg --configure -a

    # Allow overriding the version via env variable (e.g., CHROMIUM_VERSION=145.0.0.0)
    local target_version="${CHROMIUM_VERSION:-}"

    if [ -z "${target_version}" ]; then
        echo "Querying latest stable Chromium version..."
        target_version=$(curl -fsSL \
            "https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=1" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(r for r in d if r['channel']=='Stable')['version'])")
    fi

    echo "Target Chromium version: ${target_version}"

    mkdir -p "${_chrome_dir}"
    cd "${_chrome_dir}"

    cat > ".gclient" <<EOF
solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git@refs/tags/${target_version}",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
EOF

    echo "Syncing Chromium ${target_version} (shallow clone)..."
    if ! gclient sync --nohooks --no-history; then
        echo "ERROR: gclient sync failed." >&2
        exit 1
    fi

    echo "Installing Chromium system build dependencies..."
    if [ -f "${_src_dir}/build/install-build-deps.sh" ]; then
        sudo "${_src_dir}/build/install-build-deps.sh" --no-prompt
    else
        echo "WARNING: install-build-deps.sh not found." >&2
    fi

    echo "Running gclient runhooks to download toolchains..."
    if ! gclient runhooks; then
        echo "ERROR: gclient runhooks failed." >&2
        exit 1
    fi

    echo "Chromium ${target_version} fetch and toolchain verification complete."
    touch "${stamp}"
}

# ---------------------------------------------------------------------------
# apply_blutvine_patches
# ---------------------------------------------------------------------------
apply_blutvine_patches() {
    local stamp="${_src_dir}/.patched.stamp"
    [ -f "${stamp}" ] && { echo "Patches already applied"; return 0; }

    local series="${_patches_dir}/series"
    echo "Applying BlutVine patches..."

    while IFS= read -u 3 -r patch_file || [ -n "${patch_file}" ]; do
        [[ -z "${patch_file}" || "${patch_file}" =~ ^[[:space:]]*# ]] && continue
        local full_path="${_patches_dir}/${patch_file}"

        echo "  applying ${patch_file}"

        if [[ "${patch_file}" == *"skia.patch" ]]; then
            # Navigate to skia, apply, then jump back to src
            cd "${_src_dir}/third_party/skia"
            if ! patch -p1 -F3 --ignore-whitespace < "${full_path}"; then
                echo "FAILED: Skia patch ${patch_file}" >&2
                exit 1
            fi
            cd "${_src_dir}"
        else
            # Standard patches applied from src root
            if ! patch -p1 -d "${_src_dir}" -F3 --ignore-whitespace < "${full_path}"; then
                echo "FAILED: Standard patch ${patch_file}" >&2
                exit 1
            fi
        fi
    done 3< "${series}"

    touch "${stamp}"
    echo "All patches applied successfully."
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
