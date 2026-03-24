#!/bin/bash
# setup.sh
# 1. Installs System Dependencies
# 2. Prepares the Chrome environment
# 3. Fetches the Chromium source
# 4. Syncs custom scripts from BlutVine
# 5. Applies Patches (NO COMPILATION)

set -euo pipefail

# PATH CONFIGURATION
_chrome_root="${HOME}/Chrome"
_kevin_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${_chrome_root}/scripts"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Step 0: Install System Dependencies ──────────────────────────────────────
log "Updating system and installing dependencies..."
sudo apt update
sudo apt install -y git python3 devscripts equivs docker.io curl

# ── Step 1: Create Chrome Folder ─────────────────────────────────────────────
if [ ! -d "$_chrome_root" ]; then
    log "Creating Chrome project folder..."
    mkdir -p "$_chrome_root"
fi

# ── Step 2: Navigate and Fetch ───────────────────────────────────────────────
cd "$_chrome_root"

log "Step 1/2: Running initial Fetch..."
if [ -f "${_kevin_scripts}/fetch.sh" ]; then
    bash "${_kevin_scripts}/fetch.sh"
else
    die "Could not find fetch.sh at ${_kevin_scripts}/fetch.sh"
fi

# ── Step 3: Sync Scripts ─────────────────────────────────────────────────────
log "Syncing scripts into Chrome/scripts..."
mkdir -p "$_chrome_scripts"

if [ -d "$_kevin_scripts" ]; then
    cp "${_kevin_scripts}/"*.sh "$_chrome_scripts/"
    chmod +x "$_chrome_scripts/"*.sh
    log "Scripts synced."
else
    die "Source scripts folder not found: $_kevin_scripts"
fi

# ── Step 4: Run Patch ────────────────────────────────────────────────────────
log "Step 2/2: Applying patches..."
# We use the newly synced script in Chrome/scripts
bash scripts/patch.sh

log "==========================================="
log "SETUP COMPLETE: Source is fetched and patched."
log "Ready for manual build with: bash scripts/build.sh"
log "==========================================="
