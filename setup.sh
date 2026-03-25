#!/bin/bash
# setup.sh - Staging only (Prepares environment and patches, no compile)
set -euo pipefail

# ── 1. Configuration ──────────────────────────────────────────────────────────
# CHROME_ROOT is the single source of truth.
export CHROME_ROOT="${HOME}/Chrome"
_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log() { echo "==> $*"; }

# ── 2. System Prep ────────────────────────────────────────────────────────────
log "Installing system dependencies..."
sudo apt update && sudo apt install -y git python3 curl nodejs

# ── 3. Workspace Initialization ───────────────────────────────────────────────
log "Initializing workspace at ${CHROME_ROOT}..."
mkdir -p "$_chrome_scripts"

# FIX: Sync scripts BEFORE running any of them.
# This ensures fetch.sh and patch.sh run with the correct local paths.
log "Synchronizing scripts to workspace..."
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

# ── 4. Execution ──────────────────────────────────────────────────────────────
# We now run the scripts from their NEW location in the workspace.

log "Step 1: Fetching Chromium source..."
bash "$_chrome_scripts/fetch.sh"

log "Step 2: Applying Project Bifrost patches..."
bash "$_chrome_scripts/patch.sh"

log "Staging complete."
log "Source is downloaded and patched in ${CHROME_ROOT}/build/src"
log "To start the build, run: bash ${_chrome_scripts}/build.sh"
