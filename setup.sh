#!/bin/bash
# setup.sh - Staging only (No Compile)
set -euo pipefail

_chrome_root="${HOME}/Chrome"
_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${_chrome_root}/scripts"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# Step 0: System Prep
log "Installing dependencies..."
sudo apt update && sudo apt install -y git python3 devscripts equivs docker.io curl

# Step 1: Initialize Chrome Folder
if [ ! -d "$_chrome_root" ]; then
    log "Creating dedicated Chrome workspace..."
    mkdir -p "$_chrome_root"
fi

# Step 2: Enter Chrome and Fetch
cd "$_chrome_root"
log "Running Fetch inside $(pwd)..."
if [ -f "${_blutvine_scripts}/fetch.sh" ]; then
    bash "${_blutvine_scripts}/fetch.sh"
else
    die "Missing fetch.sh in ${_blutvine_scripts}"
fi

# Step 3: Sync Scripts & Patch
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "Applying patches..."
bash scripts/patch.sh

log "SUCCESS: Chrome is staged and patched in ${_chrome_root}"
