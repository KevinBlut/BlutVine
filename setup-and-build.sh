#!/bin/bash
# setup-and-build.sh - Full automation pipeline
set -euo pipefail

export CHROME_ROOT="${HOME}/Chrome"
_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log() { echo "==> $*"; }

log "1. System dependencies..."
sudo apt update && sudo apt install -y git python3 curl nodejs ninja-build

log "2. Synchronizing scripts to workspace..."
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "3. Fetching Chromium source..."
bash "$_chrome_scripts/fetch.sh"

log "4. Applying Bifrost patches..."
bash "$_chrome_scripts/patch.sh"

log "5. Executing Build..."
bash "$_chrome_scripts/build.sh"

log "Build process complete. Binaries located in ${CHROME_ROOT}/build/src/out/Default"
