#!/bin/bash
# setup.sh - Staging Environment Preparation
set -euo pipefail

# ── configuration ─────────────────────────────────────────────────────────────

export CHROME_ROOT="${HOME}/Chrome"
_blutvine_root="${HOME}/BlutVine"
_blutvine_scripts="${_blutvine_root}/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"

log() { echo "==> $*"; }

# ── 1. System Prep ────────────────────────────────────────────────────────────

log "Updating Git and installing dependencies..."
# Fix: Update Git to 2.46+ to satisfy depot_tools requirements
sudo add-apt-repository ppa:git-core/ppa -y
sudo apt update && sudo apt install -y git python3 curl nodejs

# Suppress the git version warning from gclient
export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1

# ── 2. Workspace Initialization ───────────────────────────────────────────────

log "Initializing workspace at ${CHROME_ROOT}..."
mkdir -p "$_chrome_scripts"

# FIX: Sync scripts BEFORE running any of them.
# This ensures fetch.sh and patch.sh run from the correct local context.
log "Synchronizing scripts to workspace..."
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

# ── 3. Execution ──────────────────────────────────────────────────────────────

log "Step 1: Fetching Chromium source..."
bash "$_chrome_scripts/fetch.sh"

log "Step 2: Applying patches (using ${_blutvine_root}/series)..."
bash "$_chrome_scripts/patch.sh"

log "Staging complete."
log "Source tree is prepared and patched in ${CHROME_ROOT}/build/src"
log "To compile, run: bash ${_chrome_scripts}/build.sh"
