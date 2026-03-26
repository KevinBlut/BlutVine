#!/bin/bash
# setup.sh - Staging only (No Compile)
#
# Flow:
#   1. Install system dependencies
#   2. Create ~/Chrome workspace
#   3. cd ~/Chrome
#   4. Run fetch.sh  → source lands in ~/Chrome/build/src
#   5. Install Chromium build deps (install-build-deps.sh now available)
#   6. Copy scripts to ~/Chrome/scripts/
#   7. Run patch.sh  → applies patches via ~/BlutVine/series
#
set -euo pipefail

export CHROME_ROOT="${HOME}/Chrome"
export BLUTVINE_DIR="${BLUTVINE_DIR:-${HOME}/BlutVine}"

_blutvine_scripts="${BLUTVINE_DIR}/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Step 1: Install system dependencies ───────────────────────────────────────

log "Installing system dependencies..."
sudo apt update && sudo apt install -y \
    git python3 curl ninja-build \
    devscripts equivs

if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found, installing..."
    sudo apt install -y docker.io
else
    log "Docker already installed, skipping."
fi

if ! command -v node >/dev/null 2>&1; then
    log "Node.js not found, installing..."
    sudo apt install -y nodejs
else
    log "Node.js already installed, skipping."
fi

# ── Step 2: Create Chrome workspace ───────────────────────────────────────────

log "Creating Chrome workspace at ${CHROME_ROOT}..."
mkdir -p "${CHROME_ROOT}"

# ── Step 3: cd into Chrome folder ─────────────────────────────────────────────

cd "${CHROME_ROOT}"

# ── Step 4: Fetch Chromium source ─────────────────────────────────────────────

log "Running fetch..."
[ -f "${_blutvine_scripts}/fetch.sh" ] || die "Missing fetch.sh in ${_blutvine_scripts}"
bash "${_blutvine_scripts}/fetch.sh"

# ── Step 5: Install Chromium build deps (now that src/ exists) ────────────────
# install-build-deps.sh is part of the Chromium source and covers system libs
# (libgbm-dev, libasound2-dev, etc.) that apt alone does not pull in.

_install_build_deps="${CHROME_ROOT}/build/src/build/install-build-deps.sh"
if [ -f "$_install_build_deps" ] && [ ! -f "${CHROME_ROOT}/.build_deps_installed" ]; then
    log "Installing Chromium system build dependencies..."
    sudo bash "$_install_build_deps" --no-syms --no-arm --no-chromeos-fonts --no-nacl
    touch "${CHROME_ROOT}/.build_deps_installed"
else
    log "Chromium build deps already installed or script not found, skipping."
fi

# ── Step 6: Copy scripts to Chrome folder ─────────────────────────────────────

log "Syncing scripts to ${_chrome_scripts}..."
mkdir -p "${_chrome_scripts}"
cp "${_blutvine_scripts}/"*.sh "${_chrome_scripts}/"
chmod +x "${_chrome_scripts}/"*.sh

# ── Step 7: Apply patches via BlutVine/series ─────────────────────────────────

log "Applying patches..."
bash "${_chrome_scripts}/patch.sh"

log "SUCCESS: Chrome is staged and patched in ${CHROME_ROOT}"
