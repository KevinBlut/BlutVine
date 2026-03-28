#!/bin/bash
set -euo pipefail

# Install required build dependencies before anything else.
# Safe to run repeatedly — apt-get is a no-op if already installed.
echo "Installing build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
    clang \
    lld \
    llvm \
    ninja-build \
    python3 \
    python3-pkg-resources \
    nodejs \
    curl \
    xz-utils \
    libffi-dev \
    pkg-config \
    patch

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/shared.sh"

setup_paths
check_system_deps

# clean out/ directory before build
rm -rf "${_out_dir}" || true

fetch_chromium
apply_blutvine_patches
write_gn_args
fix_tool_downloading
install_sysroot
setup_sccache
setup_toolchain
gn_gen
maybe_build
