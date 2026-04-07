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

    # Redirect googlesource URLs to GitHub mirror to avoid 403 blocks
    git config --global url."https://github.com/chromium/".insteadOf \
        "https://chromium.googlesource.com/chromium/"
    git config --global url."https://github.com/".insteadOf \
        "https://chromium.googlesource.com/"

    cat > "${_chrome_dir}/.gclient" <<GCLIENT
solutions = [
  {
    "name": "src",
    "url": "https://github.com/chromium/chromium.git@refs/tags/${version}",
    "managed": False,
    "custom_deps": {
        "src/third_party/freetype/src": None,
    },
    "custom_vars": {},
  },
]
GCLIENT

    echo "Cloning Chromium ${version} (no history)..."
    cd "${_chrome_dir}"
    gclient sync --nohooks --no-history

    echo "Installing Chromium system build dependencies..."
    sudo "${_src_dir}/build/install-build-deps.sh" --no-prompt

    echo "Running gclient runhooks (downloads toolchain)..."
    cd "${_chrome_dir}"
    gclient runhooks

    if [ ! -f "${_depot_tools_dir}/python3_bin_reldir.txt" ] && \
       [ ! -f "${_src_dir}/buildtools/python3/python3_bin_reldir.txt" ]; then
        echo "ERROR: depot_tools Python bootstrap failed!" >&2
        exit 1
    fi

    echo "Python toolchain verified."

    touch "${stamp}"
}
