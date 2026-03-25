#!/bin/bash
# setup-and-build.sh - Full Automation
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────

# CHROME_ROOT is the single source of truth for where everything lives.
# Exported so that shared.sh's repo_root() picks it up in every sub-script,
# regardless of where those scripts are physically located on disk.
export CHROME_ROOT="${HOME}/Chrome"

_blutvine_scripts="${HOME}/BlutVine/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"
_output_dir="${CHROME_ROOT}/build/src/out"

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ── Step 0: System Prep ───────────────────────────────────────────────────────

log "Updating system..."
sudo apt update && sudo apt install -y git python3 devscripts equivs curl
if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found, installing..."
    sudo apt install -y docker.io
else
    log "Docker already installed, skipping."
fi

# ── Step 1: Initialize Chrome folder ─────────────────────────────────────────

log "Initializing Chrome workspace at ${CHROME_ROOT}..."
mkdir -p "$CHROME_ROOT"
cd "$CHROME_ROOT"

# ── Step 2: Fetch (gclient sync) ──────────────────────────────────────────────
# fetch.sh sources shared.sh which reads CHROME_ROOT, so all paths resolve
# under ~/Chrome regardless of where the script file lives.

log "Fetching Chromium source..."
bash "${_blutvine_scripts}/fetch.sh"

# ── Step 3: Copy scripts then Patch ──────────────────────────────────────────
# Scripts are copied to ~/Chrome/scripts/ so everything is self-contained.
# patch.sh and build.sh will also read CHROME_ROOT, so paths stay consistent.

log "Syncing scripts to ${_chrome_scripts}..."
mkdir -p "$_chrome_scripts"
cp "${_blutvine_scripts}/"*.sh "$_chrome_scripts/"
chmod +x "$_chrome_scripts/"*.sh

log "Applying patches..."
bash "$_chrome_scripts/patch.sh"

# ── Step 4: Build ─────────────────────────────────────────────────────────────

log "Starting compilation..."
bash "$_chrome_scripts/build.sh"

# ── Step 5: Archive Result ────────────────────────────────────────────────────

log "Compressing build output..."
if [ -d "${_output_dir}/Default" ]; then
    cd "${_output_dir}"
    tar -czf chrome_build.tar.gz Default/
    log "Archive created: ${_output_dir}/chrome_build.tar.gz"
    du -sh chrome_build.tar.gz
else
    die "Build output not found at ${_output_dir}/Default"
fi
