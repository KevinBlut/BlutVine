#!/bin/bash
# setup_and_run.sh
# 1. Installs System Dependencies
# 2. Prepares the Chrome environment
# 3. Fetches the Chromium source
# 4. Syncs custom scripts from KevinBlut
# 5. Runs the Patch and Build pipeline

set -euo pipefail

_chrome_root="${HOME}/Chrome"
_kevin_scripts="${HOME}/KevinBlut/scripts"
_chrome_scripts="${_chrome_root}/scripts"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Step 0: Install System Dependencies ──────────────────────────────────────
log "Updating system and installing dependencies..."
sudo apt update
sudo apt install -y git python3 devscripts equivs docker.io curl

# Ensure the current user can use Docker
if ! groups | grep -q "\bdocker\b"; then
    log "Adding user to docker group... (You might need to re-login for this to take effect)"
    sudo usermod -aG docker "$USER" || true
fi

# ── Step 1: Create Chrome Folder ─────────────────────────────────────────────
if [ ! -d "$_chrome_root" ]; then
    log "Creating Chrome project folder..."
    mkdir -p "$_chrome_root"
else
    log "Chrome folder already exists."
fi

# ── Step 2: Navigate and Fetch ───────────────────────────────────────────────
cd "$_chrome_root"

log "Step 1/3: Running initial Fetch..."
if [ -f "${_kevin_scripts}/fetch.sh" ]; then
    # We pass the first run to fetch.sh to get the source
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

# ── Step 4: Run Patch & Build ────────────────────────────────────────────────
log "Step 2/3: Applying patches..."
bash scripts/patch.sh

log "Step 3/3: Starting build (autoninja)..."
bash scripts/build.sh

log "==========================================="
log "PROCESS COMPLETE: Project Bifrost is ready."
log "==========================================="
