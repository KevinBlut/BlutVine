#!/bin/bash
# setup_and_run.sh
# 1. Prepares the Chrome environment
# 2. Fetches the Chromium source
# 3. Syncs custom scripts from KevinBlut
# 4. Runs the Patch and Build pipeline

set -euo pipefail

_chrome_root="${HOME}/Chrome"
_kevin_scripts="${HOME}/KevinBlut/scripts"
_chrome_scripts="${_chrome_root}/scripts"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Step 1: Create Chrome Folder ─────────────────────────────────────────────
if [ ! -d "$_chrome_root" ]; then
    log "Creating Chrome project folder..."
    mkdir -p "$_chrome_root"
else
    log "Chrome folder already exists."
fi

# ── Step 2: Navigate and Fetch ───────────────────────────────────────────────
# We assume fetch.sh is already available in KevinBlut/scripts 
# so we can run it even before the "Sync" happens.
cd "$_chrome_root"

log "Step 1/3: Running initial Fetch..."
# Check if scripts folder exists in KevinBlut to find the fetcher
if [ -f "${_kevin_scripts}/fetch.sh" ]; then
    bash "${_kevin_scripts}/fetch.sh"
else
    die "Could not find fetch.sh at ${_kevin_scripts}/fetch.sh"
fi

# ── Step 3: Sync Scripts ─────────────────────────────────────────────────────
log "Syncing scripts into Chrome/scripts..."
mkdir -p "$_chrome_scripts"

if [ -d "$_kevin_scripts" ]; then
    # Copy all .sh files from KevinBlut/scripts to Chrome/scripts
    cp "${_kevin_scripts}/"*.sh "$_chrome_scripts/"
    chmod +x "$_chrome_scripts/"*.sh
    log "Scripts synced and permissions set."
else
    die "Source scripts folder not found: $_kevin_scripts"
fi

# ── Step 4: Run Patch & Build ────────────────────────────────────────────────
log "Step 2/3: Applying patches..."
bash scripts/patch.sh

log "Step 3/3: Starting build (autoninja)..."
bash scripts/build.sh

log "==========================================="
log "PROCESS COMPLETE: Project Bifrost is ready."
log "Binary: ${_chrome_root}/build/src/out/Default/chrome"
log "==========================================="