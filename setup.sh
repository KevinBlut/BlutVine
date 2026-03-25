#!/bin/bash
# setup.sh - Staging only (Prepares environment and patches, no compile)
set -euo pipefail

export CHROME_ROOT="${HOME}/Chrome"
_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log() { echo "==> $*"; }

log "1. Installing system dependencies..."
sudo apt update && sudo apt install -y git python3 curl nodejs

log "2. Initializing workspace at ${CHROME_ROOT}..."
mkdir -p "$_chrome_scripts"

log "3. Synchronizing scripts to workspace..."
# We sync first so fetch/patch run from the local Chrome/scripts context
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "4. Step 1: Fetching Chromium source..."
bash "$_chrome_scripts/fetch.sh"

log "5. Step 2: Applying Project Bifrost patches (Excluding 013/015)..."
bash "$_chrome_scripts/patch.sh"

log "Staging complete. Patches applied (minus 013/015)."
log "To compile, run: bash ${_chrome_scripts}/build.sh"
