#!/bin/bash
# StarMade downloader — resolves a build from the official CDN and extracts it
# into the current directory. Shared by the egg install script and by start.sh's
# AUTO_UPDATE path. Existing world/server data is preserved (files are merged,
# never wiped).
#
# Inputs (env):
#   STARMADE_BRANCH   release | dev | pre | archive   (default: release)
#   STARMADE_VERSION  a specific version e.g. 0.304.7, or "latest" (default: latest)
#
# CDN layout (verified against the StarMade launcher source + live CDN):
#   Build index : http://files.star-made.org/<branch>buildindex
#                 lines: "VER#BUILD ./build/starmade-build_TS" (latest = last line)
#   Build zip   : http://files-origin.star-made.org/<buildPath>.zip
set -euo pipefail

BRANCH="${STARMADE_BRANCH:-release}"
WANT="${STARMADE_VERSION:-latest}"
INDEX_BASE="http://files.star-made.org"
ORIGIN_BASE="http://files-origin.star-made.org"

case "$BRANCH" in
  release | dev | pre | archive) ;;
  *) echo "[download] Unknown branch '$BRANCH' — falling back to release."; BRANCH=release ;;
esac

log() { printf '[download] %s\n' "$*"; }

log "Branch=$BRANCH  Version=$WANT"
INDEX="$(curl -fsSL --retry 3 "${INDEX_BASE}/${BRANCH}buildindex")"
[ -n "$INDEX" ] || { echo "[download] ERROR: empty build index at ${INDEX_BASE}/${BRANCH}buildindex"; exit 1; }

# Pick the build line. "latest" (or empty) => last non-blank line.
if [ "$WANT" = "latest" ] || [ -z "$WANT" ]; then
  LINE="$(printf '%s\n' "$INDEX" | grep -E '\S' | tail -1)"
else
  LINE="$(printf '%s\n' "$INDEX" | grep -F "${WANT}#" | tail -1 || true)"
  if [ -z "$LINE" ]; then
    log "Version '$WANT' not found on $BRANCH — using latest instead."
    LINE="$(printf '%s\n' "$INDEX" | grep -E '\S' | tail -1)"
  fi
fi
[ -n "$LINE" ] || { echo "[download] ERROR: could not resolve a build."; exit 1; }

VER="$(printf '%s' "$LINE" | cut -d'#' -f1)"
BUILDPATH="$(printf '%s' "$LINE" | awk '{print $2}' | sed 's#^\./##')"
ZIP_URL="${ORIGIN_BASE}/${BUILDPATH}.zip"
log "Resolved version ${VER}  ->  ${ZIP_URL}"

# Stage on the server volume (cwd), NOT /tmp: Wings mounts the container's /tmp as
# a small tmpfs (~100 MB default), so downloading the ~600 MB build there dies with
# "curl: (23) Failure writing output to destination". The volume has the real disk quota.
TMP="$(mktemp -d "${PWD}/.sm-download.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

log "Downloading…"
if command -v aria2c >/dev/null 2>&1; then
  aria2c -x8 -s8 --console-log-level=warn --summary-interval=10 \
    -d "$TMP" -o sm.zip "$ZIP_URL"
else
  curl -fL --retry 3 --retry-delay 5 --progress-bar -o "$TMP/sm.zip" "$ZIP_URL"
fi

log "Extracting…"
mkdir -p "$TMP/x"
unzip -oq "$TMP/sm.zip" -d "$TMP/x"
rm -f "$TMP/sm.zip"   # free ~600 MB before the copy so the volume peak stays low

# The current build zip is rooted (StarMade.jar at top). Stay tolerant of a future
# build that wraps everything in a single top-level directory.
if [ -f "$TMP/x/StarMade.jar" ]; then
  SRC="$TMP/x"
else
  JAR="$(find "$TMP/x" -maxdepth 3 -name StarMade.jar | head -1 || true)"
  [ -n "$JAR" ] || { echo "[download] ERROR: StarMade.jar not found in the downloaded archive."; exit 1; }
  SRC="$(dirname "$JAR")"
fi

# Merge into the target dir (cwd), overwriting game files but keeping world data.
cp -a "$SRC/." .
[ -f StarMade.jar ] || { echo "[download] ERROR: StarMade.jar missing after extraction."; exit 1; }

log "StarMade ${VER} ready in $(pwd)."
