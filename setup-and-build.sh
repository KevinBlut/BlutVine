#!/bin/bash
# setup_and_run.sh
# 1. Installs System Dependencies
# 2. Prepares the Chrome environment
# 3. Fetches, Patches, and Builds Chromium 146
# 4. Compresses the output for distribution

set -euo pipefail

# PATH CONFIGURATION
_chrome_root="${HOME}/Chrome"
_kevin_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${_chrome_root}/scripts"
_output_dir="${_chrome_root}/build/src/out"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Step 0: Install System Dependencies ──────────────────────────────────────
log "Updating system and installing dependencies..."
sudo apt update
sudo apt install -y git python3 devscripts equivs docker.io curl

# Ensure the current user can use Docker
if ! groups | grep -q "\bdocker\b"; then
    log "Adding user to docker group..."
    sudo usermod -aG docker "$USER" || true
fi

# ── Step 1: Create Chrome Folder ─────────────────────────────────────────────
if [ ! -d "$_chrome_root" ]; then
    log "Creating Chrome project folder..."
    mkdir -p "$_chrome_root"
fi

# ── Step 2: Navigate and Fetch ───────────────────────────────────────────────
cd "$_chrome_root"

log "Step 1/4: Running initial Fetch..."
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

# ── Step 4: Run Patch & Build ────────────────────────────────────────────────
log "Step 2/4: Applying patches..."
bash scripts/patch.sh

log "Step 3/4: Starting build (autoninja)..."
bash scripts/build.sh

# ── Step 5: Compress Result ──────────────────────────────────────────────────
log "Step 4/4: Compressing build output..."

if [ -d "${_output_dir}/Default" ]; then
    cd "${_output_dir}"
    tar -czf chrome_build.tar.gz Default/
    
    log "Compression complete!"
    log "Final Archive: ${_output_dir}/chrome_build.tar.gz"
    du -sh chrome_build.tar.gz
else
    die "Build output directory not found at ${_output_dir}/Default. Build may have failed."
fi

log "==========================================="
log "PROCESS COMPLETE: Project Bifrost is packed."
log "==========================================="
