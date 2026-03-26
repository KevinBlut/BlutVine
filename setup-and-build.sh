#!/bin/bash
# setup-and-build.sh - Full Automation
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────

export CHROME_ROOT="${HOME}/Chrome"

_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"
_output_dir="${CHROME_ROOT}/build/src/out"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Step 0: System Prep ───────────────────────────────────────────────────────

log "Updating system..."
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
    log "install-build-deps.sh not present yet — will be available after fetch."
fi

# ── Step 1: Initialize Chrome folder ─────────────────────────────────────────

log "Initializing Chrome workspace at ${CHROME_ROOT}..."
mkdir -p "$CHROME_ROOT"
cd "$CHROME_ROOT"

# ── Step 2: Fetch (gclient sync) ──────────────────────────────────────────────

log "Fetching Chromium source..."
bash "${_blutvine_scripts}/fetch.sh"

# ── Step 3: Install build deps (now that install-build-deps.sh exists) ────────

if [ -f "$_install_build_deps" ] && [ ! -f "${CHROME_ROOT}/.build_deps_installed" ]; then
    log "Installing Chromium system build dependencies..."
    sudo bash "$_install_build_deps" --no-syms --no-arm --no-chromeos-fonts --no-nacl
    touch "${CHROME_ROOT}/.build_deps_installed"
fi

# ── Step 4: Copy scripts then Patch ──────────────────────────────────────────

log "Syncing scripts to ${_chrome_scripts}..."
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "Applying patches..."
bash "$_chrome_scripts/patch.sh"

# ── Step 5: Build ─────────────────────────────────────────────────────────────

log "Starting compilation..."
bash "$_chrome_scripts/build.sh"

# ── Step 6: Archive Result ────────────────────────────────────────────────────

log "Compressing build output..."
if [ -f "${_output_dir}/Default/chrome" ]; then
    cd "${_output_dir}"
    tar -czf chrome_build.tar.gz Default/
    log "Archive created: ${_output_dir}/chrome_build.tar.gz"
    du -sh chrome_build.tar.gz
else
    die "Build output not found — chrome binary missing from ${_output_dir}/Default"
fi
