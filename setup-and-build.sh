#!/bin/bash
# setup-and-build.sh
set -euo pipefail

export CHROME_ROOT="${HOME}/Chrome"
_blutvine_root="${HOME}/BlutVine"
_blutvine_scripts="${_blutvine_root}/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"
_output_dir="${CHROME_ROOT}/build/src/out/Default"

log() { echo "==> $*"; }

log "1. System dependencies..."
sudo apt update && sudo apt install -y git python3 curl nodejs ninja-build

log "2. Syncing scripts..."
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "3. Fetching & Patching..."
bash "$_chrome_scripts/fetch.sh"
bash "$_chrome_scripts/patch.sh"

log "4. Starting full compilation..."
bash "$_chrome_scripts/build.sh"

log "5. Archiving build..."
if [ -f "${_output_dir}/chrome" ]; then
    cd "$(dirname "$_output_dir")"
    tar -czf chrome_build.tar.gz Default/
    log "Build archived at: $(dirname "$_output_dir")/chrome_build.tar.gz"
fi
