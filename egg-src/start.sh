#!/bin/bash
# StarMade runtime wrapper — Pelican / Wings startup command target.
#
# Runs inside the game container (working dir = /home/container) as the server's
# main process. Responsibilities, in order:
#   1. (optional) AUTO_UPDATE: pull the latest build for the configured branch.
#   2. Sync selected egg variables into server.cfg (StarMade's `KEY = value` format).
#   3. Pick JVM arguments based on the container's actual Java major version.
#   4. exec the StarMade dedicated server so stdin (console / `/shutdown`) reaches it.
#
# Everything here is portable POSIX-ish bash so it also runs unmodified during the
# local boot test. It is embedded verbatim into egg-starmade.json by build-egg.sh.
set -euo pipefail

cd "$(dirname "$0")"

log() { printf '[start.sh] %s\n' "$*"; }

# ── Helpers ────────────────────────────────────────────────────────────────────

# Normalize a truthy string to StarMade's literal true/false.
to_bool() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1 | true | yes | on) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

# Set (or append) a `KEY = value` entry in server.cfg. Portable — rewrites the
# file rather than using `sed -i`, so it behaves the same on GNU and BSD sed.
set_cfg() {
  local key="$1" val="$2" tmp found=0 line
  tmp="$(mktemp)"
  if [ -f server.cfg ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if printf '%s' "$line" | grep -qE "^[[:space:]]*${key}[[:space:]]*="; then
        printf '%s = %s\n' "$key" "$val" >>"$tmp"
        found=1
      else
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <server.cfg
  fi
  [ "$found" -eq 0 ] && printf '%s = %s\n' "$key" "$val" >>"$tmp"
  mv "$tmp" server.cfg
}

# Detect the container's Java major version (8, 17, 21, …).
java_major() {
  local v
  v="$(java -version 2>&1 | head -1 | sed -E 's/.*version "([^"]+)".*/\1/')"
  case "$v" in
    1.*) printf '%s' "$v" | cut -d. -f2 ;; # "1.8.0_x" -> 8
    *) printf '%s' "$v" | cut -d. -f1 ;;   # "21.0.1"  -> 21
  esac
}

# ── 1. Optional in-place update ────────────────────────────────────────────────

if [ "$(to_bool "${AUTO_UPDATE:-0}")" = "true" ]; then
  if command -v unzip >/dev/null 2>&1; then
    log "AUTO_UPDATE enabled — checking ${STARMADE_BRANCH:-release} branch for a newer build…"
    if bash ./sm-download.sh; then
      log "Update check complete."
    else
      log "Update failed; continuing with the currently installed build."
    fi
  else
    log "AUTO_UPDATE requested but 'unzip' is unavailable in this image — skipping."
  fi
fi

if [ ! -f StarMade.jar ]; then
  log "ERROR: StarMade.jar not found in $(pwd). Reinstall the server from the panel."
  exit 1
fi

# ── 2. Apply configuration from egg variables ──────────────────────────────────

# StarMade binds inside the container; listen on every interface so the mapped
# port is reachable regardless of Wings' network mode.
set_cfg SERVER_LISTEN_IP "all"

# The public/display name is SERVER_LIST_NAME (there is no "SERVER_NAME" key —
# StarMade silently drops unknown keys when it rewrites server.cfg).
[ -n "${SERVER_NAME:-}" ] && set_cfg SERVER_LIST_NAME "${SERVER_NAME}"
[ -n "${SERVER_DESCRIPTION:-}" ] && set_cfg SERVER_LIST_DESCRIPTION "${SERVER_DESCRIPTION}"
# Announcing to the public list only works when a reachable hostname is set.
[ -n "${SERVER_HOSTNAME:-}" ] && set_cfg HOST_NAME_TO_ANNOUNCE_TO_SERVER_LIST "${SERVER_HOSTNAME}"
[ -n "${MAX_CLIENTS:-}" ] && set_cfg MAX_CLIENTS "${MAX_CLIENTS}"
set_cfg ANNOUNCE_SERVER_TO_SERVERLIST "$(to_bool "${ANNOUNCE_SERVER_TO_SERVERLIST:-0}")"
set_cfg USE_STARMADE_AUTHENTICATION "$(to_bool "${USE_STARMADE_AUTHENTICATION:-0}")"
set_cfg REQUIRE_STARMADE_AUTHENTICATION "$(to_bool "${REQUIRE_STARMADE_AUTHENTICATION:-0}")"
set_cfg USE_WHITELIST "$(to_bool "${USE_WHITELIST:-0}")"

if [ -n "${SUPER_ADMIN_PASSWORD:-}" ]; then
  set_cfg SUPER_ADMIN_PASSWORD_USE "true"
  set_cfg SUPER_ADMIN_PASSWORD "${SUPER_ADMIN_PASSWORD}"
else
  set_cfg SUPER_ADMIN_PASSWORD_USE "false"
fi

# Generic passthrough: any container env var named SMCFG_<KEY> writes <KEY> to
# server.cfg. Lets power users set any of StarMade's ~210 config options from the
# panel (add a variable with env var e.g. SMCFG_SECTOR_SIZE) without this egg
# having to enumerate them all.
while IFS='=' read -r _name _val; do
  case "$_name" in
    SMCFG_*) [ -n "${_name#SMCFG_}" ] && set_cfg "${_name#SMCFG_}" "$_val" ;;
  esac
done < <(env)

# ── 3. JVM arguments ───────────────────────────────────────────────────────────

JAVA_MAJOR="$(java_major)"
JVM_ARGS=()
# Modern StarMade (>= 0.3, Java 21) loads through StarLoader: the jar is its own
# javaagent (Premain-Class api.starloader.StarAgent) and needs three java.base
# packages opened for reflection. These are exactly the args the StarMade launcher
# and the official server scripts use — omitting the agent is why old eggs break.
# Legacy Java 8 builds (< 0.3) predate StarLoader and take none of these.
if [ "${JAVA_MAJOR:-8}" -ge 9 ] 2>/dev/null; then
  JVM_ARGS+=(
    -javaagent:StarMade.jar
    --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED
    --add-opens=java.base/java.nio=ALL-UNNAMED
    --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED
  )
fi

# Heap sizing. SERVER_MEMORY is the container's hard memory limit (MB); StarMade
# uses substantial off-heap/direct memory, so reserve headroom to avoid OOM kills.
MEM="${SERVER_MEMORY:-4096}"
HEADROOM="${HEAP_HEADROOM_MB:-1024}"
# SERVER_MEMORY reaches us via the startup command (env SERVER_MEMORY={{SERVER_MEMORY}} …);
# warn loudly if it looks unset so a silent tiny heap can't slip by again.
if ! [ "$MEM" -gt 0 ] 2>/dev/null; then
  log "WARNING: SERVER_MEMORY is unset/invalid ('${SERVER_MEMORY:-}') — is the startup command passing it? Falling back to 4096 MB."
  MEM=4096
fi
# A headroom >= memory would produce a negative/tiny heap; cap it instead.
if [ "$HEADROOM" -ge "$MEM" ] 2>/dev/null; then
  log "WARNING: HEAP_HEADROOM_MB ($HEADROOM) >= memory ($MEM MB); capping headroom to MEM/8."
  HEADROOM=$((MEM / 8))
fi
XMX=$((MEM - HEADROOM))
[ "$XMX" -lt 512 ] && XMX=512
XMS=512
[ "$XMS" -gt "$XMX" ] && XMS="$XMX"

read -r -a EXTRA <<<"${EXTRA_JVM_ARGS:-}"

# StarMade takes its port ONLY from the -port: flag (colon form) — server.cfg has
# no port key — so this is how Wings' allocated port takes effect. Default 4242.
PORT="${SERVER_PORT:-4242}"

log "Java ${JAVA_MAJOR} | heap ${XMS}M–${XMX}M | port ${PORT}"
set -x
exec java "${JVM_ARGS[@]}" -Xms"${XMS}"M -Xmx"${XMX}"M "${EXTRA[@]}" \
  -jar StarMade.jar -server -port:"${PORT}"
