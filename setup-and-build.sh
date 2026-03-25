#!/bin/bash
# setup-and-build.sh - Full Automation (Fetch, Patch, and Compile)
set -euo pipefail

# ── 1. Configuration ──────────────────────────────────────────────────────────
export CHROME_ROOT="${HOME}/Chrome"
_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"
_output_dir="${CHROME_ROOT}/build/src/out/Default"

log() { echo "==> $*"; }

# ── 2. System Prep ────────────────────────────────────────────────────────────
log "Step 0: Installing system dependencies..."
sudo apt update && sudo apt install -y git python3 curl nodejs ninja-build

# ── 3. Workspace & Script Sync ────────────────────────────────────────────────
log "Step 1: Initializing workspace and syncing scripts..."
mkdir -p "$_chrome_scripts"

# FIX: We sync scripts FIRST so the pipeline is self-contained in ~/Chrome
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

# ── 4. Execution ──────────────────────────────────────────────────────────────
# We run everything from the NEW location to ensure path consistency.

log "Step 2: Fetching Chromium source..."
bash "$_chrome_scripts/fetch.sh"

log "Step 3: Applying patches (Excluding 013/015)..."
bash "$_chrome_scripts/patch.sh"

log "Step 4: Starting compilation (This will take a while)..."
bash "$_chrome_scripts/build.sh"

# ── 5. Post-Build ─────────────────────────────────────────────────────────────
log "Step 5: Archiving build output..."
if [ -f "${_output_dir}/chrome" ]; then
    cd "$(dirname "$_output_dir")"
    tar -czf chrome_build.tar.gz Default/
    log "Success! Archive created at: $(dirname "$_output_dir")/chrome_build.tar.gz"
else
    echo "ERROR: Build failed. Chrome binary not found in $_output_dir"
    exit 1
fi
