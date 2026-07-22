#!/usr/bin/env bash
# Migrate an existing StarMade Docker setup into a Pelican-managed server.
# Sourced by setup.sh. Depends on lib/common.sh and lib/pelican-api.sh.
#
# Reads a target directory containing a docker-compose.yml and/or .env in the
# StarMade-Community "server scripts" layout (STARMADE_DIR, SERVER_PORT,
# JVM_MIN_HEAP / JVM_MAX_HEAP, CONTAINER_NAME) — but is tolerant of missing keys.
# It maps those to a new Pelican server, then copies the existing world/server
# data into the new server's Wings volume before first boot. The source is never
# modified or deleted.

WINGS_VOLUMES="${WINGS_VOLUMES:-/var/lib/pelican/volumes}"

# "16g" / "8192m" / "4096" -> megabytes
heap_to_mb() {
  local v="${1:-}" n unit
  v="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  n="${v//[!0-9]/}"; unit="${v//[0-9]/}"
  [ -n "$n" ] || { printf '0'; return; }
  case "$unit" in
    g|gb) printf '%s' "$((n * 1024))" ;;
    m|mb|"") printf '%s' "$n" ;;
    k|kb) printf '%s' "$((n / 1024))" ;;
    *) printf '%s' "$n" ;;
  esac
}

# Read KEY=VALUE from a .env-style file, stripping quotes/comments. Echoes value.
env_val() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  grep -E "^[[:space:]]*${key}=" "$file" | tail -1 \
    | sed -E "s/^[[:space:]]*${key}=//; s/[[:space:]]*#.*$//; s/^[\"']//; s/[\"']$//" \
    | tr -d '\r'
}

# parse_existing_setup DIR -> sets IMP_PORT, IMP_MEM_MB, IMP_DATA_DIR, IMP_NAME
parse_existing_setup() {
  local dir="$1" envf
  [ -d "$dir" ] || die "Not a directory: $dir"
  envf="$dir/.env"; [ -f "$envf" ] || envf="$dir/.env.example"

  IMP_PORT="$(env_val "$envf" SERVER_PORT)"
  IMP_NAME="$(env_val "$envf" CONTAINER_NAME)"
  local data max
  data="$(env_val "$envf" STARMADE_DIR)"
  max="$(env_val "$envf" JVM_MAX_HEAP)"

  # Resolve STARMADE_DIR relative to the setup dir when it isn't absolute or points
  # at the placeholder from .env.example.
  if [ -z "$data" ] || [ "$data" = "/path/to/your/starmade/server" ]; then
    if [ -d "$dir/server-data" ]; then data="$dir/server-data"; fi
  fi
  [ "${data#/}" = "$data" ] && [ -n "$data" ] && data="$dir/$data"

  IMP_DATA_DIR="$data"
  IMP_PORT="${IMP_PORT:-4242}"
  IMP_NAME="${IMP_NAME:-StarMade (imported)}"
  IMP_MEM_MB="$(heap_to_mb "${max:-8g}")"
  [ "${IMP_MEM_MB:-0}" -ge 1024 ] 2>/dev/null || IMP_MEM_MB=4096

  log "Detected from $dir:"
  printf '    name=%s  port=%s  memory=%sMB  data=%s\n' \
    "$IMP_NAME" "$IMP_PORT" "$IMP_MEM_MB" "${IMP_DATA_DIR:-<none found>}"
}

# migrate_world_data SRC UUID — copy world/server data into the server's volume.
migrate_world_data() {
  local src="$1" uuid="$2" dest="$WINGS_VOLUMES/$uuid"
  [ -n "$uuid" ] || die "No server UUID — cannot locate the Wings volume."
  [ -d "$src" ]  || { warn "Source data dir '$src' not found — skipping data migration (new server starts empty)."; return 0; }
  need_root
  [ -d "$dest" ] || die "Volume dir $dest does not exist yet. Ensure Wings created the server, then retry the migration."

  require_cmd rsync || { log "Installing rsync…"; $SUDO apt-get update -qq && $SUDO apt-get install -y -qq rsync || die "rsync required."; }

  warn "About to copy world/server data:"
  printf '    from: %s\n    into: %s\n' "$src" "$dest"
  confirm "Proceed? (source is only read, never modified)" y || { warn "Migration skipped."; return 0; }

  # Copy game data but not the StarMade binaries — those come from the egg install.
  $SUDO rsync -a --info=progress2 \
    --exclude 'StarMade.jar' --exclude 'version.txt' --exclude 'lib/' --exclude 'native/' --exclude 'data/' \
    "${src%/}/" "${dest%/}/"

  # Match ownership to whatever Wings uses for this volume.
  local owner
  owner="$(stat -c '%u:%g' "$dest" 2>/dev/null || echo '988:988')"
  $SUDO chown -R "$owner" "$dest"
  ok "World data migrated. Owner set to $owner."
}
