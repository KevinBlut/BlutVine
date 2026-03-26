#!/bin/bash
# setup.sh - Staging only (No Compile)
set -euo pipefail

export CHROME_ROOT="${HOME}/Chrome"

_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Step 0: System Prep ───────────────────────────────────────────────────────

log "Installing dependencies..."
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

# Install Chromium's own build dependency list if available.
# This covers system libraries (libgbm-dev, libasound2-dev, etc.) that the
# Chromium build system needs but that apt alone won't pull in.
_install_build_deps="${CHROME_ROOT}/build/src/build/install-build-deps.sh"
if [ -f "$_install_build_deps" ]; then
    log "Installing Chromium build deps via install-build-deps.sh..."
    sudo bash "$_install_build_deps" --no-syms --no-arm --no-chromeos-fonts --no-nacl
else
    log "install-build-deps.sh not present yet (run after fetch.sh if needed)."
fi

# ── Step 1: Initialize Chrome Folder ─────────────────────────────────────────

log "Initializing Chrome workspace at ${CHROME_ROOT}..."
mkdir -p "$CHROME_ROOT"
cd "$CHROME_ROOT"

# ── Step 2: Fetch (gclient sync) ──────────────────────────────────────────────

log "Running fetch..."
if [ -f "${_blutvine_scripts}/fetch.sh" ]; then
    bash "${_blutvine_scripts}/fetch.sh"
else
    die "Missing fetch.sh in ${_blutvine_scripts}"
fi

# ── Step 3: Sync Scripts & Patch ──────────────────────────────────────────────

log "Syncing scripts to ${_chrome_scripts}..."
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "Applying patches..."
bash "$_chrome_scripts/patch.sh"

log "SUCCESS: Chrome is staged and patched in ${CHROME_ROOT}"
