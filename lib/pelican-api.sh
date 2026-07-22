#!/usr/bin/env bash
# Pelican application-API client for provisioning a StarMade server.
# Sourced by setup.sh. Depends on lib/common.sh, curl and jq.
#
# Pelican's application API is Pterodactyl-v1 compatible:
#   Auth:   Authorization: Bearer <APPLICATION_API_KEY>
#   Base:   <PANEL_URL>/api/application
# Endpoints used:
#   GET  /users                      GET /nodes            GET /nests
#   GET  /nests/{nest}/eggs          GET /nodes/{id}/allocations
#   POST /servers
#
# NOTE: Pelican has no public API to *import* an egg — that is a one-time UI action
# (Admin → Eggs → Import → From File/URL). This client assumes the egg is already
# imported and resolves its id by name (default "StarMade").

PANEL_URL="${PANEL_URL:-}"
APP_API_KEY="${APP_API_KEY:-}"

pelican_require() {
  require_cmd curl || die "curl is required for the Pelican API."
  require_cmd jq   || die "jq is required for the Pelican API."
  [ -n "$PANEL_URL" ]   || ask PANEL_URL "Panel URL (e.g. https://panel.example.com)"
  PANEL_URL="${PANEL_URL%/}"
  [ -n "$APP_API_KEY" ] || ask_secret APP_API_KEY "Application API key (Admin → API Keys)"
  [ -n "$PANEL_URL" ] && [ -n "$APP_API_KEY" ] || die "Panel URL and API key are required."
}

# api METHOD PATH [BODY_JSON] — echoes response body; sets API_HTTP to status code.
api() {
  local method="$1" path="$2" body="${3:-}" tmp code
  tmp="$(mktemp)"
  if [ -n "$body" ]; then
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer ${APP_API_KEY}" \
      -H "Accept: application/json" -H "Content-Type: application/json" \
      -d "$body" "${PANEL_URL}/api/application${path}")"
  else
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer ${APP_API_KEY}" \
      -H "Accept: application/json" \
      "${PANEL_URL}/api/application${path}")"
  fi
  API_HTTP="$code"
  cat "$tmp"; rm -f "$tmp"
}

pelican_check_auth() {
  local out
  out="$(api GET /users?per_page=1)"
  case "$API_HTTP" in
    200) ok "Authenticated to $PANEL_URL" ;;
    401|403) die "Auth failed (HTTP $API_HTTP). Check the application API key." ;;
    *) die "Panel not reachable (HTTP $API_HTTP) at $PANEL_URL. Response: $(printf '%s' "$out" | head -c 200)" ;;
  esac
}

# Resolve an egg id by name (scans all nests). Echoes the id; empty if not found.
pelican_find_egg_id() {
  local want="${1:-StarMade}" nests id
  nests="$(api GET /nests?per_page=200)"
  for id in $(printf '%s' "$nests" | jq -r '.data[].attributes.id'); do
    local eggs match
    eggs="$(api GET "/nests/${id}/eggs?per_page=200")"
    # `first(...)` (not `| head`) so a closed pipe can't SIGPIPE jq under pipefail.
    match="$(printf '%s' "$eggs" | jq -r --arg n "$want" \
      'first(.data[] | select((.attributes.name // "") | ascii_downcase == ($n|ascii_downcase)) | .attributes.id) // empty')"
    if [ -n "$match" ]; then printf '%s' "$match"; return 0; fi
  done
  return 1
}

# Pick the first free (unassigned) allocation on a node, preferring one whose port
# matches $1. Echoes "allocId port"; empty if none free.
pelican_pick_allocation() {
  local node="$1" want_port="${2:-}" allocs
  allocs="$(api GET "/nodes/${node}/allocations?per_page=500")"
  if [ -n "$want_port" ]; then
    local line
    line="$(printf '%s' "$allocs" | jq -r --arg p "$want_port" \
      'first(.data[] | select((.attributes.assigned==false) and ((.attributes.port|tostring)==$p)) | "\(.attributes.id) \(.attributes.port)") // empty')"
    [ -n "$line" ] && { printf '%s' "$line"; return 0; }
  fi
  printf '%s' "$allocs" | jq -r \
    'first(.data[] | select(.attributes.assigned==false) | "\(.attributes.id) \(.attributes.port)") // empty'
}

# List helpers for interactive selection.
pelican_list_users() { api GET /users?per_page=200 | jq -r '.data[].attributes | "\(.id)\t\(.username)\t\(.email)"'; }
pelican_list_nodes() { api GET /nodes?per_page=200 | jq -r '.data[].attributes | "\(.id)\t\(.name)\t(\(.fqdn))"'; }

# Create the server. Expects the caller to have exported the variables below.
# Echoes the created server's identifier on success.
# On success sets CREATED_IDENTIFIER and CREATED_UUID (globals) and echoes the id.
# SRV_START (default true) controls start_on_completion — set to false when data
# must be migrated into the volume before first boot.
pelican_create_server() {
  local body start="${SRV_START:-true}"
  body="$(jq -n \
    --arg name    "$SRV_NAME" \
    --argjson user "$SRV_USER" \
    --argjson egg  "$SRV_EGG" \
    --arg image   "$SRV_IMAGE" \
    --arg startup "bash start.sh" \
    --argjson mem  "$SRV_MEMORY" \
    --argjson disk "$SRV_DISK" \
    --argjson cpu  "$SRV_CPU" \
    --argjson alloc "$SRV_ALLOC" \
    --argjson env  "$SRV_ENV" \
    --argjson start "$start" \
    '{
      name: $name, user: $user, egg: $egg,
      docker_image: $image, startup: $startup,
      environment: $env,
      limits:       { memory: $mem, swap: 0, disk: $disk, io: 500, cpu: $cpu },
      feature_limits:{ databases: 0, allocations: 1, backups: 3 },
      allocation:   { default: $alloc },
      start_on_completion: $start
    }')"
  local out
  out="$(api POST /servers "$body")"
  if [ "$API_HTTP" = "201" ] || [ "$API_HTTP" = "200" ]; then
    CREATED_UUID="$(printf '%s' "$out" | jq -r '.attributes.uuid // ""')"
    CREATED_IDENTIFIER="$(printf '%s' "$out" | jq -r '.attributes.identifier // ""')"
    printf '%s' "${CREATED_IDENTIFIER:-created}"
    return 0
  fi
  err "Server creation failed (HTTP $API_HTTP):"
  printf '%s\n' "$out" | jq -r '(.errors // [] | .[] | "  - \(.detail // .code)")' 2>/dev/null || printf '%s\n' "$out" | head -c 400 >&2
  return 1
}
