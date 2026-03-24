#!/bin/bash
# setup_and_run.sh - Full Automation
set -euo pipefail

_chrome_root="${HOME}/Chrome"
_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${_chrome_root}/scripts"
_output_dir="${_chrome_root}/build/src/out"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# Step 0: System Prep
log "Updating system..."
sudo apt update && sudo apt install -y git python3 devscripts equivs docker.io curl

# Step 1: Initialize & CD
mkdir -p "$_chrome_root"
cd "$_chrome_root"

# Step 2: Fetch
log "Fetching Chromium source..."
bash "${_blutvine_scripts}/fetch.sh"

# Step 3: Sync & Patch
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "Applying patches..."
bash scripts/patch.sh

# Step 4: Build
log "Starting compilation..."
bash scripts/build.sh

# Step 5: Archive Result
log "Compressing build output..."
if [ -d "${_output_dir}/Default" ]; then
    cd "${_output_dir}"
    tar -czf chrome_build.tar.gz Default/
    log "Archive created: ${_output_dir}/chrome_build.tar.gz"
    du -sh chrome_build.tar.gz
else
    die "Build output not found!"
fi
