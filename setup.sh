#!/usr/bin/env bash
# StarMade-Pelican — interactive setup.
#
# Turnkey path: install Docker + Pelican Panel + Wings if missing, then provision a
# StarMade server via the Pelican API. Can also migrate an existing StarMade Docker
# setup (compose/.env + world data) into a Pelican-managed server.
#
# Usage:
#   ./setup.sh                 # interactive menu
#   ./setup.sh --yes           # accept defaults where possible (non-interactive)
#   ./setup.sh --answers FILE  # load/save answers from FILE (see templates/answers.env.example)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/prereqs.sh"
. "$REPO_ROOT/lib/pelican-api.sh"
. "$REPO_ROOT/lib/import-docker.sh"

EGG_PATH="$REPO_ROOT/egg/egg-starmade.json"
EGG_RAW_URL="https://raw.githubusercontent.com/garretreichenbach/StarMade-Pelican/main/egg/egg-starmade.json"
USER_EMAIL_DEFAULT="garretreichenbach@gmail.com"
ASSUME_YES=0

# ── args ───────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --answers) ANSWERS_FILE="$2"; shift ;;
    --answers=*) ANSWERS_FILE="${1#*=}" ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) warn "Unknown argument: $1" ;;
  esac
  shift
done
export ASSUME_YES
[ -n "${ANSWERS_FILE:-}" ] && load_answers "$ANSWERS_FILE" || true

# ── egg import guidance (no public API for egg import) ─────────────────────────
egg_import_help() {
  hr
  log "Import the StarMade egg into your panel (one-time, in the UI):"
  cat <<EOF
  Admin → Eggs → Import Egg, then either:
    • From File: upload  $EGG_PATH
    • From URL:  $EGG_RAW_URL
  After importing, the egg appears as "StarMade" and this script can find it by name.
EOF
  [ -f "$EGG_PATH" ] && ok "Local egg present: $EGG_PATH" || warn "Egg not built yet — run: bash egg-src/build-egg.sh"
  hr
}

# ── provisioning ───────────────────────────────────────────────────────────────
provision_server() {
  pelican_require
  pelican_check_auth

  # Resolve the egg id (by name), else guide import.
  local egg_id
  egg_id="$(pelican_find_egg_id "StarMade" || true)"
  if [ -z "$egg_id" ]; then
    warn "No egg named 'StarMade' found on the panel yet."
    egg_import_help
    ask egg_id "Enter the StarMade egg's ID once imported (Admin → Eggs → StarMade → the number in the URL)"
    [ -n "$egg_id" ] || die "An egg id is required to provision."
  else
    ok "Found StarMade egg (id=$egg_id)."
  fi

  hr; log "Owner + node"
  pelican_list_users | sed 's/^/    user  /'
  ask SRV_USER "Owner user ID" "1"
  pelican_list_nodes | sed 's/^/    node  /'
  local node_id; ask node_id "Node ID to deploy on" "1"

  hr; log "Server settings"
  : "${SRV_NAME:=}"; ask SRV_NAME "Server name" "StarMade Server"
  local game_port;   ask game_port "Game port (must have a free allocation on the node)" "4242"
  ask SRV_MEMORY "Memory limit (MB)" "6144"
  ask SRV_DISK   "Disk limit (MB)"   "10240"
  ask SRV_CPU    "CPU limit (%, 0=unlimited)" "0"

  hr; log "StarMade options"
  local branch version maxc announce useauth reqauth wl superpw headroom extra descr hostname
  ask branch   "Update branch (release/dev/pre/archive)" "release"
  ask version  "Version (or 'latest')" "latest"
  ask descr    "Server description (optional)" ""
  ask maxc     "Max players" "32"
  hostname=""
  if confirm "Announce to the public server list?" n; then
    announce=1
    ask hostname "Public hostname/IP clients connect to (required for announce)" ""
  else
    announce=0
  fi
  confirm "Enable StarMade account authentication?" n && useauth=1 || useauth=0
  reqauth=0; [ "$useauth" = 1 ] && { confirm "Require authenticated accounts?" n && reqauth=1 || reqauth=0; }
  confirm "Use whitelist?" n && wl=1 || wl=0
  ask_secret superpw "Super-admin password (blank = disabled)"
  ask headroom "Heap headroom held back from -Xmx (MB)" "1024"
  ask extra    "Extra JVM args (optional)" ""

  # Build the egg environment object.
  SRV_ENV="$(jq -n \
    --arg b "$branch" --arg v "$version" \
    --arg n "$SRV_NAME" --arg d "$descr" --arg host "$hostname" --arg mc "$maxc" \
    --arg an "$announce" --arg ua "$useauth" --arg ra "$reqauth" --arg wl "$wl" \
    --arg pw "$superpw" --arg hr "$headroom" --arg ex "$extra" \
    '{
      STARMADE_BRANCH: $b, STARMADE_VERSION: $v, AUTO_UPDATE: "0",
      SERVER_NAME: $n, SERVER_DESCRIPTION: $d, SERVER_HOSTNAME: $host, MAX_CLIENTS: $mc,
      ANNOUNCE_SERVER_TO_SERVERLIST: $an,
      USE_STARMADE_AUTHENTICATION: $ua, REQUIRE_STARMADE_AUTHENTICATION: $ra,
      USE_WHITELIST: $wl, SUPER_ADMIN_PASSWORD: $pw,
      HEAP_HEADROOM_MB: $hr, EXTRA_JVM_ARGS: $ex
    }')"

  # Pick a free allocation (prefer the requested port).
  local alloc_line
  alloc_line="$(pelican_pick_allocation "$node_id" "$game_port")"
  [ -n "$alloc_line" ] || die "No free allocation on node $node_id (create one for port $game_port in Admin → Nodes → Allocations)."
  SRV_ALLOC="${alloc_line%% *}"
  ok "Using allocation id=$SRV_ALLOC (port ${alloc_line##* })."

  SRV_EGG="$egg_id"; SRV_IMAGE="ghcr.io/pterodactyl/yolks:java_21"
  export SRV_NAME SRV_USER SRV_EGG SRV_IMAGE SRV_MEMORY SRV_DISK SRV_CPU SRV_ALLOC SRV_ENV

  hr
  local id
  if id="$(pelican_create_server)"; then
    ok "Server created: ${id}  →  ${PANEL_URL}/server/${id}"
    [ -n "${ANSWERS_FILE:-}" ] && { save_answer "$ANSWERS_FILE" PANEL_URL "$PANEL_URL"; save_answer "$ANSWERS_FILE" SRV_USER "$SRV_USER"; }
  else
    die "Provisioning failed — see the error above."
  fi
}

# ── migration ──────────────────────────────────────────────────────────────────
migrate_docker_setup() {
  local dir
  ask dir "Path to your existing StarMade docker setup (dir with docker-compose.yml/.env)" ""
  [ -n "$dir" ] || die "A path is required."
  parse_existing_setup "$dir"

  pelican_require; pelican_check_auth
  local egg_id; egg_id="$(pelican_find_egg_id "StarMade" || true)"
  [ -n "$egg_id" ] || { egg_import_help; ask egg_id "StarMade egg id"; }

  pelican_list_users | sed 's/^/    user  /'; ask SRV_USER "Owner user ID" "1"
  pelican_list_nodes | sed 's/^/    node  /'; local node_id; ask node_id "Node ID" "1"

  SRV_NAME="$IMP_NAME"; SRV_MEMORY="$IMP_MEM_MB"; SRV_DISK="20480"; SRV_CPU="0"
  SRV_EGG="$egg_id"; SRV_IMAGE="ghcr.io/pterodactyl/yolks:java_21"
  SRV_START="false"   # don't boot until world data is in place
  SRV_ENV="$(jq -n --arg n "$IMP_NAME" \
    '{STARMADE_BRANCH:"release",STARMADE_VERSION:"latest",AUTO_UPDATE:"0",
      SERVER_NAME:$n,MAX_CLIENTS:"32",ANNOUNCE_SERVER_TO_SERVERLIST:"0",
      USE_STARMADE_AUTHENTICATION:"0",REQUIRE_STARMADE_AUTHENTICATION:"0",
      USE_WHITELIST:"0",SUPER_ADMIN_PASSWORD:"",HEAP_HEADROOM_MB:"1024",EXTRA_JVM_ARGS:""}')"

  local alloc_line; alloc_line="$(pelican_pick_allocation "$node_id" "$IMP_PORT")"
  [ -n "$alloc_line" ] || die "No free allocation for port $IMP_PORT on node $node_id."
  SRV_ALLOC="${alloc_line%% *}"
  export SRV_NAME SRV_USER SRV_EGG SRV_IMAGE SRV_MEMORY SRV_DISK SRV_CPU SRV_ALLOC SRV_ENV SRV_START

  local id
  id="$(pelican_create_server)" || die "Server creation failed."
  ok "Server shell created: $id (uuid=$CREATED_UUID). Waiting for the egg install to finish before migrating data."
  warn "Let the install complete in the panel (Console shows 'StarMade install complete'), then continue."
  confirm "Has the install finished?" y || { warn "Re-run migration later: it only needs the world data copy."; return 0; }

  migrate_world_data "$IMP_DATA_DIR" "$CREATED_UUID"
  ok "Migration done. Start the server from the panel."
}

# ── menu ───────────────────────────────────────────────────────────────────────
main_menu() {
  hr
  printf '%s\n' "${C_BOLD}StarMade × Pelican setup${C_RESET}"
  cat <<'EOF'
  1) Full setup      — install prereqs (if missing) then provision a server
  2) Prereqs only    — Docker + Pelican Panel + Wings
  3) Provision a server (Pelican already installed)
  4) Migrate an existing StarMade Docker setup
  5) Egg import help / rebuild
  6) Quit
EOF
  local choice; ask choice "Choose" "1"
  case "$choice" in
    1) is_debian_like || warn "Non-Debian OS: prereq auto-install may not apply; provisioning still works."
       ensure_all_prereqs; provision_server ;;
    2) ensure_all_prereqs ;;
    3) provision_server ;;
    4) migrate_docker_setup ;;
    5) egg_import_help ;;
    6) exit 0 ;;
    *) warn "Unknown choice."; main_menu ;;
  esac
}

main_menu
