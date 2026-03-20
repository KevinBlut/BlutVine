#!/bin/bash
set -uo pipefail

# ─────────────────────────────────────────────
# CONFIG — edit these before running
BLUTVINE_DIR="$HOME/BlutVine"          # folder containing your custom patches and series file
NINJA_JOBS=$(nproc)                    # auto-detect core count
# ─────────────────────────────────────────────

REPO_DIR="$HOME/ungoogled-chromium-portablelinux"
PATCHES_DIR="$REPO_DIR/patches"
SHARED_SH="$REPO_DIR/scripts/shared.sh"

echo "==> [0/6] Waiting for apt lock to be released (unattended-upgrades)..."
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "  apt is locked by another process, waiting..."
    sleep 3
done
echo "  Lock is free, continuing..."

echo "==> [1/6] Updating system and installing dependencies..."
sudo apt update || echo "WARNING: apt update had issues, continuing..."
sudo apt install -y git python3 devscripts equivs || echo "WARNING: some packages may already be installed, continuing..."
# Docker is pre-installed on vast.ai, skip if already present
if ! command -v docker &>/dev/null; then
    sudo apt install -y docker.io
else
    echo "Docker already installed, skipping"
fi

echo "==> [2/6] Cloning ungoogled-chromium-portablelinux..."
if [ -d "$REPO_DIR" ]; then
    echo "Repo already exists at $REPO_DIR, skipping clone"
else
    git clone https://github.com/ungoogled-software/ungoogled-chromium-portablelinux.git "$REPO_DIR"
fi

cd "$REPO_DIR"

echo "==> [3/6] Initialising submodules..."
git submodule update --init --recursive

echo "==> [4/6] Copying BlutVine patches into patches/ folder..."
if [ ! -d "$BLUTVINE_DIR" ]; then
    echo "ERROR: BlutVine folder not found at $BLUTVINE_DIR"
    echo "Please place your BlutVine folder there and re-run."
    exit 1
fi

# copy patch files (everything except the series file)
find "$BLUTVINE_DIR" -type f ! -name "series" -exec cp {} "$PATCHES_DIR/" \;

# append BlutVine series entries to existing series file
if [ -f "$BLUTVINE_DIR/series" ]; then
    echo "" >> "$PATCHES_DIR/series"
    cat "$BLUTVINE_DIR/series" >> "$PATCHES_DIR/series"
    echo "Appended BlutVine series entries to patches/series"
else
    echo "WARNING: No series file found in $BLUTVINE_DIR, skipping series merge"
fi

echo "==> [5/6] Patching shared.sh to use -j${NINJA_JOBS}..."
# replace the ninja line in maybe_build() with the -j flag
sed -i "s|ninja -C out/Default chrome chromedriver|ninja -j${NINJA_JOBS} -C out/Default chrome chromedriver|g" "$SHARED_SH"

# verify the patch was applied
if grep -q "ninja -j${NINJA_JOBS}" "$SHARED_SH"; then
    echo "ninja -j${NINJA_JOBS} applied successfully"
else
    echo "ERROR: Failed to patch shared.sh"
    exit 1
fi

echo "==> [6/6] Starting docker build..."
cd "$REPO_DIR"
scripts/docker-build.sh

echo ""
echo "========================================="
echo "Build complete! Verifying chrome binary..."
CHROME_BIN="$REPO_DIR/build/src/out/Default/chrome"

if [ -f "$CHROME_BIN" ]; then
    echo "chrome binary found: $(ls -lh $CHROME_BIN)"
    echo ""
    echo "Safe to compress. Run:"
    echo "  tar -czf chrome_build.tar.gz \\"
    echo "    build/src/out/Default/chrome \\"
    echo "    build/src/out/Default/chrome-wrapper \\"
    echo "    build/src/out/Default/chromedriver \\"
    echo "    build/src/out/Default/chrome_crashpad_handler \\"
    echo "    build/src/out/Default/*.pak \\"
    echo "    build/src/out/Default/*.so* \\"
    echo "    build/src/out/Default/*.bin \\"
    echo "    build/src/out/Default/*.json \\"
    echo "    build/src/out/Default/locales/"
else
    echo "WARNING: chrome binary not found — build may have failed."
    exit 1
fi
