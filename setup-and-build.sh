#!/bin/bash
# setup-and-build.sh - Full Automation (Fetch, Patch, and Compile)
set -euo pipefail

# ── 1. Configuration ──────────────────────────────────────────────────────────
# Single source of truth for the build workspace
export CHROME_ROOT="${HOME}/Chrome"
_blutvine_root="${HOME}/BlutVine"
_blutvine_scripts="${_blutvine_root}/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"
_output_dir="${CHROME_ROOT}/build/src/out/Default"

log() { echo "==> $*"; }

# ── 2. System Prep ────────────────────────────────────────────────────────────
log "Step 0: Updating Git and installing dependencies..."

# Fix: Update Git to 2.46+ to satisfy depot_tools and suppress warnings
sudo add-apt-repository ppa:git-core/ppa -y
sudo apt update && sudo apt install -y git python3 curl nodejs ninja-build

# Suppress the git version warning from gclient during the fetch phase
export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1

# ── 3. Workspace & Script Sync ────────────────────────────────────────────────
log "Step 1: Initializing workspace and syncing scripts..."
mkdir -p "$_chrome_scripts"

# FIX: Sync scripts FIRST. 
# This ensures that fetch.sh, patch.sh, and build.sh all run from 
# within the Chrome/scripts context with consistent relative paths.
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

# ── 4. Execution ──────────────────────────────────────────────────────────────
# We execute the pipeline using the scripts now located in the workspace.

log "Step 2: Fetching Chromium source..."
bash "$_chrome_scripts/fetch.sh"

log "Step 3: Applying Bifrost patches (via series file)..."
# Note: patch.sh now looks for the series file at ~/BlutVine/series
bash "$_chrome_scripts/patch.sh"

log "Step 4: Starting compilation (This may take several hours)..."
bash "$_chrome_scripts/build.sh"

# ── 5. Post-Build ─────────────────────────────────────────────────────────────
log "Step 5: Verifying and archiving build output..."

if [ -f "${_output_dir}/chrome" ]; then
    log "Build successful! Creating archive..."
    cd "$(dirname "$_output_dir")"
    tar -czf chrome_build.tar.gz Default/
    log "Final archive located at: $(dirname "$_output_dir")/chrome_build.tar.gz"
    
    # Optional: Display the size of the final package
    du -sh "chrome_build.tar.gz"
else
    echo "ERROR: Build failed. Chrome binary not found in ${_output_dir}"
    exit 1
fi
