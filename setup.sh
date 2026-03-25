#!/bin/bash
# setup.sh
set -euo pipefail

export CHROME_ROOT="${HOME}/Chrome"
_blutvine_root="${HOME}/BlutVine"
_blutvine_scripts="${_blutvine_root}/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log() { echo "==> $*"; }

log "1. System dependencies..."
sudo apt update && sudo apt install -y git python3 curl nodejs

log "2. Workspace Sync..."
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "3. Running Fetch..."
bash "$_chrome_scripts/fetch.sh"

log "4. Applying Patches (using ${_blutvine_root}/series)..."
bash "$_chrome_scripts/patch.sh"

log "Staging complete. Ready to build."
