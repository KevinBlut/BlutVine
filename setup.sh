#!/bin/bash
# setup.sh - Staging only (No Compile)
set -euo pipefail

# CHROME_ROOT is the single source of truth for where everything lives.
# Exported so that shared.sh's repo_root() picks it up in every sub-script,
# regardless of where those scripts are physically located on disk.
export CHROME_ROOT="${HOME}/Chrome"

_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# Step 0: System Prep
log "Installing dependencies..."
sudo apt update && sudo apt install -y git python3 devscripts equivs curl
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

# Step 1: Initialize Chrome Folder
log "Initializing Chrome workspace at ${CHROME_ROOT}..."
mkdir -p "$CHROME_ROOT"
cd "$CHROME_ROOT"

# Step 2: Fetch (gclient sync)
log "Running fetch..."
if [ -f "${_blutvine_scripts}/fetch.sh" ]; then
    bash "${_blutvine_scripts}/fetch.sh"
else
    die "Missing fetch.sh in ${_blutvine_scripts}"
fi

# Step 3: Sync Scripts & Patch
log "Syncing scripts to ${_chrome_scripts}..."
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "Applying patches..."
bash "$_chrome_scripts/patch.sh"

log "SUCCESS: Chrome is staged and patched in ${CHROME_ROOT}"
