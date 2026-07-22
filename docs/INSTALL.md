# Turnkey install walkthrough

Target: a fresh **x86‑64 Debian/Ubuntu** server. `setup.sh` automates everything that can be
automated and prints explicit, one‑time guided steps for the parts that are inherently
panel‑UI driven (creating an API key, creating a Node, pointing Wings at it).

```bash
git clone https://github.com/StarMade-Community/StarMade-Pelican.git
cd StarMade-Pelican
./setup.sh          # choose "Full setup"
```

## What "Full setup" does

### 1. Docker
Installs Docker Engine + compose via the official `get.docker.com` script if not already present.

### 2. Pelican Panel (Docker, SQLite)
Deploys the panel to `/opt/pelican` from [`templates/panel-compose.yml`](../templates/panel-compose.yml)
(image `ghcr.io/pelican-dev/panel:latest`, SQLite by default — no separate database container).
You'll be asked for the public URL and a Let's Encrypt email.

Then, one‑time in the browser + one command:

1. Open the URL and complete the web installer if prompted.
2. Create your admin user:
   ```bash
   cd /opt/pelican && sudo docker compose exec panel php artisan p:user:make
   ```
3. **Admin → API Keys → create an Application API key** (read/write). Keep it handy.

### 3. Wings
Downloads the Wings binary for your architecture to `/usr/local/bin/wings` and installs a
`wings.service` systemd unit. Then, one‑time:

1. **Admin → Nodes → Create Node** (FQDN = this host).
2. Node → **Configuration** → copy the `wings configure …` command and run it on this host.
3. `sudo systemctl enable --now wings`
4. Create an **Allocation** on the node for your StarMade game port (e.g. `4242`).

### 4. Import the egg (one‑time)
**Admin → Eggs → Import** → From File `egg/egg-starmade.json` (or the raw GitHub URL).

### 5. Provision
`setup.sh` continues into provisioning: it authenticates with your API key, finds the StarMade
egg by name, and asks for owner, node, port, memory, and StarMade options, then creates the
server via `POST /api/application/servers`.

## Re‑running / automation

Everything is idempotent — re‑running skips installed components. For repeatable runs, copy
[`templates/answers.env.example`](../templates/answers.env.example) to `answers.env` and:

```bash
./setup.sh --yes --answers answers.env
```

`answers.env` is git‑ignored. The API key is not stored unless you opt in.

## Notes

- The panel install uses SQLite for simplicity. For a large deployment, switch to MariaDB per
  the [Pelican docs](https://pelican.dev/docs) and re‑point the compose file.
- If you already run Pelican, skip straight to **Provision a server**.
