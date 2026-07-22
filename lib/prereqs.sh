#!/usr/bin/env bash
# Prerequisite detection + installation for a turnkey Pelican host.
# Sourced by setup.sh. Depends on lib/common.sh. Linux (Debian/Ubuntu) target.
#
# Everything here is idempotent: each step first checks whether the component is
# already present and skips it if so. Steps that are inherently panel-UI driven
# (creating the admin user's API key, creating a Node, configuring Wings against
# that node) are printed as explicit guided actions rather than faked.

PELICAN_DIR="${PELICAN_DIR:-/opt/pelican}"

# ── Docker ─────────────────────────────────────────────────────────────────────
ensure_docker() {
  if require_cmd docker && docker compose version >/dev/null 2>&1; then
    ok "Docker + compose already installed ($(docker --version | awk '{print $3}' | tr -d ,))."
    return 0
  fi
  log "Installing Docker Engine (official convenience script)…"
  confirm "Run the official get.docker.com install script now?" y || die "Docker is required."
  need_root
  curl -fsSL https://get.docker.com | $SUDO sh || die "Docker install failed."
  $SUDO systemctl enable --now docker 2>/dev/null || true
  ok "Docker installed."
}

# ── Panel (Docker compose, SQLite) ─────────────────────────────────────────────
ensure_panel() {
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^pelican-panel$'; then
    ok "Pelican Panel container already running."
    return 0
  fi
  need_root
  log "Deploying Pelican Panel to $PELICAN_DIR …"
  local app_url le_email detected default_url host
  detected="$(detect_public_ip)"
  default_url="http://${detected:-localhost}"
  [ -n "$detected" ] && log "Detected this server's public IP: ${detected}"
  ask app_url "Public URL for the PANEL itself (its own address on ports 80/443 — not a game port)" "$default_url"
  # Normalize: ensure a scheme and drop any trailing slash.
  case "$app_url" in http://* | https://*) ;; *) app_url="http://$app_url" ;; esac
  app_url="${app_url%/}"
  # Typo guard: Pelican builds its Caddy vhost from this host, so a wrong host makes
  # every page a blank 200. Flag a mismatch against the detected IP before deploying.
  host="${app_url#*://}"; host="${host%%[:/]*}"
  if [ -n "$detected" ] && [ "$host" != "$detected" ] && [ "$host" != "localhost" ]; then
    warn "Entered host '${host}' ≠ this server's detected public IP '${detected}'."
    confirm "Use '${host}' anyway?" n || { app_url="http://${detected}"; ok "Using http://${detected}"; }
  fi
  ask le_email "Email for Let's Encrypt (used only for https:// URLs)" "$USER_EMAIL_DEFAULT"

  $SUDO mkdir -p "$PELICAN_DIR"
  $SUDO cp "$REPO_ROOT/templates/panel-compose.yml" "$PELICAN_DIR/compose.yml"
  $SUDO sed -i \
    -e "s#__APP_URL__#${app_url}#g" \
    -e "s#__LE_EMAIL__#${le_email}#g" \
    "$PELICAN_DIR/compose.yml"

  ( cd "$PELICAN_DIR" && $SUDO docker compose up -d ) || die "Panel compose up failed."
  ok "Panel container starting. Give it ~30s to run migrations."

  # Self-check: Caddy only serves the panel for the APP_URL host, so probe locally
  # with that Host header. A 2xx/3xx with a body = good; an empty 200 = the host is
  # wrong (the classic mistyped-IP → blank-page trap).
  local host_only resp code size served=0
  host_only="${app_url#*://}"; host_only="${host_only%%[:/]*}"
  log "Verifying the panel answers for host ${host_only}…"
  for _ in $(seq 1 12); do
    resp="$(curl -s -o /dev/null -w '%{http_code} %{size_download}' -H "Host: ${host_only}" --max-time 5 http://127.0.0.1/ 2>/dev/null || echo '000 0')"
    code="${resp% *}"; size="${resp##* }"
    case "$code" in 2* | 3*) [ "${size:-0}" -gt 0 ] 2>/dev/null && { served=1; break; } ;; esac
    sleep 3
  done
  if [ "$served" = 1 ]; then
    ok "Panel is serving (HTTP ${code}) for ${host_only} → ${app_url}"
  else
    warn "Panel returned an empty response for host '${host_only}'."
    warn "If the page is blank in your browser, APP_URL is wrong. Fix it with:"
    warn "  sudo sed -i 's#\"http://[^\"]*\"#\"${app_url}\"#' ${PELICAN_DIR}/compose.yml && (cd ${PELICAN_DIR} && sudo docker compose up -d)"
  fi

  hr
  warn "One-time panel setup (in the browser + one command):"
  cat <<EOF
  1. Open ${app_url} and complete the web installer if prompted.
  2. Create your admin user:
       cd $PELICAN_DIR && ${SUDO:+sudo }docker compose exec panel php artisan p:user:make
  3. Log in → Admin → API Keys → create an *Application* API key (read/write).
     You'll paste that key into this script for provisioning.
EOF
  hr
  PANEL_URL="${PANEL_URL:-$app_url}"
}

# ── Wings ──────────────────────────────────────────────────────────────────────
ensure_wings() {
  if require_cmd wings || [ -x /usr/local/bin/wings ]; then
    ok "Wings already installed."
    return 0
  fi
  need_root
  local arch asset
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "Unsupported CPU architecture for Wings: $(uname -m)." ;;
  esac
  asset="wings_linux_${arch}"
  log "Installing Wings ($asset)…"
  $SUDO mkdir -p /etc/pelican /var/lib/pelican /var/log/pelican
  $SUDO curl -fL -o /usr/local/bin/wings \
    "https://github.com/pelican-dev/wings/releases/latest/download/${asset}" || die "Wings download failed."
  $SUDO chmod +x /usr/local/bin/wings

  # systemd unit (started only after the node config exists).
  $SUDO tee /etc/systemd/system/wings.service >/dev/null <<'UNIT'
[Unit]
Description=Pelican Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT
  $SUDO systemctl daemon-reload
  ok "Wings binary + service installed."

  hr
  warn "One-time node setup (in the panel, then one command here):"
  cat <<'EOF'
  1. In the panel: Admin → Nodes → Create Node (FQDN = this host, ports 8080/2022).
  2. Open the node → Configuration tab → copy the `wings configure ...` command.
  3. Run that command on THIS host (writes /etc/pelican/config.yml), then:
       sudo systemctl enable --now wings
  4. Back in the panel the node should show green. Create at least one Allocation
     on the node for the StarMade game port (e.g. 4242).
EOF
  hr
}

ensure_all_prereqs() {
  ensure_docker
  ensure_panel
  ensure_wings
}
