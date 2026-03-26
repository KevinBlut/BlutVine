#!/bin/bash
# setup-and-build.sh - Full Automation
#
# Flow:
#   1. Install system dependencies
#   2. Create ~/Chrome workspace
#   3. cd ~/Chrome
#   4. Run fetch.sh  → source lands in ~/Chrome/build/src
#   5. Install Chromium build deps (install-build-deps.sh now available)
#   6. Copy scripts to ~/Chrome/scripts/
#   7. Run patch.sh  → applies patches via ~/BlutVine/series
#   8. Run build.sh  → compile chrome + chromedriver
#   9. Compress build output
#
set -euo pipefail

export CHROME_ROOT="${HOME}/Chrome"
export BLUTVINE_DIR="${BLUTVINE_DIR:-${HOME}/BlutVine}"

_blutvine_scripts="${BLUTVINE_DIR}/scripts"
_chrome_scripts="${CHROME_ROOT}/scripts"
_output_dir="${CHROME_ROOT}/build/src/out"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Step 1: Install system dependencies ───────────────────────────────────────

# Hard-kill anything holding the dpkg lock — vast.ai images often leave
# unattended-upgrades running or with a stale lock file on first boot
log "Clearing dpkg locks..."
sudo systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
sudo systemctl disable unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
sudo kill -9 $(sudo lsof /var/lib/dpkg/lock-frontend 2>/dev/null | awk 'NR>1{print $2}') 2>/dev/null || true
sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
sudo dpkg --configure -a || true

log "Installing system dependencies..."
sudo apt update
sudo apt --fix-broken install -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    --allow-downgrades --allow-change-held-packages \
    git python3 curl ninja-build \
    devscripts equivs

if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found, installing..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        --allow-downgrades --allow-change-held-packages \
        docker.io
else
    log "Docker already installed, skipping."
fi

if ! command -v node >/dev/null 2>&1; then
    log "Node.js not found, installing..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        --allow-downgrades --allow-change-held-packages \
        nodejs
else
    log "Node.js already installed, skipping."
fi

# ── Step 2: Create Chrome workspace ───────────────────────────────────────────

log "Creating Chrome workspace at ${CHROME_ROOT}..."
mkdir -p "${CHROME_ROOT}"

# ── Step 3: cd into Chrome folder ─────────────────────────────────────────────

cd "${CHROME_ROOT}"

# ── Step 4: Fetch Chromium source ─────────────────────────────────────────────

log "Fetching Chromium source..."
[ -f "${_blutvine_scripts}/fetch.sh" ] || die "Missing fetch.sh in ${_blutvine_scripts}"
bash "${_blutvine_scripts}/fetch.sh"

# ── Step 5: Install Chromium build deps (now that src/ exists) ────────────────

_install_build_deps="${CHROME_ROOT}/build/src/build/install-build-deps.sh"
if [ -f "$_install_build_deps" ] && [ ! -f "${CHROME_ROOT}/.build_deps_installed" ]; then
    log "Installing Chromium system build dependencies..."
    sudo DEBIAN_FRONTEND=noninteractive bash "$_install_build_deps" \
        --no-syms --no-arm --no-chromeos-fonts --no-nacl \
        2>&1 | tee "${CHROME_ROOT}/install-build-deps.log" || \
        die "install-build-deps.sh failed. Check ${CHROME_ROOT}/install-build-deps.log"
    touch "${CHROME_ROOT}/.build_deps_installed"
else
    log "Chromium build deps already installed or script not found, skipping."
fi

# ── Step 6: Copy scripts to Chrome folder ─────────────────────────────────────

log "Syncing scripts to ${_chrome_scripts}..."
mkdir -p "${_chrome_scripts}"
cp "${_blutvine_scripts}/"*.sh "${_chrome_scripts}/"
chmod +x "${_chrome_scripts}/"*.sh

# ── Step 7: Apply patches via BlutVine/series ─────────────────────────────────

log "Applying patches..."
bash "${_chrome_scripts}/patch.sh"

# ── Step 8: Build ─────────────────────────────────────────────────────────────

log "Starting compilation..."
bash "${_chrome_scripts}/build.sh"

# ── Step 9: Compress build output ─────────────────────────────────────────────

log "Compressing build output..."
if [ -f "${_output_dir}/Default/chrome" ]; then
    cd "${_output_dir}"
    tar -czf chrome_build.tar.gz Default/
    log "Archive created: ${_output_dir}/chrome_build.tar.gz"
    du -sh chrome_build.tar.gz
else
    die "Build output not found — chrome binary missing from ${_output_dir}/Default"
fi
