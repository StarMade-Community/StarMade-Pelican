#!/bin/bash
# StarMade egg — installation script.
#
# Runs in the Pelican/Wings install container (ghcr.io/pelican-eggs/installers:debian)
# with the server's data volume mounted at /mnt/server (this maps to /home/container
# when the server runs). Its job: lay down the runtime helper scripts, then download
# and extract the requested StarMade build.
#
# NOTE: This file is a template. build-egg.sh replaces the two __EMBED_* markers with
# heredocs that write sm-download.sh and start.sh, so the generated egg is fully
# self-contained (no dependency on this repo at install time).
set -euo pipefail

echo "=== StarMade install: branch=${STARMADE_BRANCH:-release} version=${STARMADE_VERSION:-latest} ==="

mkdir -p /mnt/server
cd /mnt/server

# --- write helper scripts (populated by build-egg.sh) --------------------------
# __EMBED_SM_DOWNLOAD__
# __EMBED_START_SH__

# --- download + extract the build ----------------------------------------------
bash ./sm-download.sh

echo "=== StarMade install complete ==="
ls -la StarMade.jar version.txt start.sh sm-download.sh 2>/dev/null || true
