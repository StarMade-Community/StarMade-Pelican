#!/bin/bash
# Generate egg/egg-starmade.json from the sources in egg-src/.
#
# The install script (egg.base.json -> scripts.installation.script) is assembled by
# taking install.sh and replacing its __EMBED_* markers with heredocs that write
# sm-download.sh and start.sh into /mnt/server. This keeps a single source of truth
# (the standalone .sh files, which are independently testable) while producing a
# fully self-contained egg.
#
# Requires: bash, jq. Usage: ./egg-src/build-egg.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SRC_DIR/.." && pwd)"
OUT="$REPO_DIR/egg/egg-starmade.json"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required."; exit 1; }

RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED"' EXIT

# Assemble the install script by expanding the embed markers. Quoted heredoc
# delimiters (single-quoted) mean the embedded file contents are written verbatim,
# with no shell expansion at install time.
awk \
  -v smdl_file="$SRC_DIR/sm-download.sh" \
  -v start_file="$SRC_DIR/start.sh" '
  function dump(file,   line) {
    while ((getline line < file) > 0) print line
    close(file)
  }
  /# __EMBED_SM_DOWNLOAD__/ {
    print "cat > sm-download.sh <<'"'"'SM_DL_EOF'"'"'"
    dump(smdl_file)
    print "SM_DL_EOF"
    print "chmod +x sm-download.sh"
    next
  }
  /# __EMBED_START_SH__/ {
    print "cat > start.sh <<'"'"'SM_START_EOF'"'"'"
    dump(start_file)
    print "SM_START_EOF"
    print "chmod +x start.sh"
    next
  }
  { print }
' "$SRC_DIR/install.sh" > "$RENDERED"

# Stamp exported_at. Date is intentionally the only nondeterministic field.
EXPORTED="$(date -u +%Y-%m-%dT%H:%M:%S+0000)"

mkdir -p "$REPO_DIR/egg"
jq \
  --rawfile script "$RENDERED" \
  --arg exported "$EXPORTED" \
  '.scripts.installation.script = $script | .exported_at = $exported' \
  "$SRC_DIR/egg.base.json" > "$OUT"

echo "Wrote $OUT"
jq empty "$OUT" && echo "Valid JSON."
