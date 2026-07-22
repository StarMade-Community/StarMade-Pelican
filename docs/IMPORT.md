# Migrating an existing StarMade Docker setup

`setup.sh` → **Migrate an existing StarMade Docker setup** brings an existing server (e.g. the
[StarMade‑Community server scripts](https://github.com/StarMade-Community/StarMade-Server-Scripts)
`docker-compose` layout) under Pelican management, including its world.

## What it reads

Point it at the directory containing your `docker-compose.yml` / `.env`. It tolerantly parses:

| Key | Used for |
| --- | --- |
| `SERVER_PORT` | Chooses/needs a matching free allocation on the node |
| `JVM_MAX_HEAP` (e.g. `16g`) | Memory limit for the new server (converted to MB) |
| `CONTAINER_NAME` | Default server name |
| `STARMADE_DIR` | Source of the world/server data to copy |

## What it does

1. Creates a Pelican StarMade server with those settings, **without starting it**
   (`start_on_completion: false`) so data can be placed before first boot.
2. Waits for the egg install to finish (fresh StarMade binaries land in the volume).
3. Copies your world/server data from `STARMADE_DIR` into the server's Wings volume
   (`/var/lib/pelican/volumes/<uuid>/`) with `rsync`, then fixes ownership to match the volume.
   - **Excluded** from the copy: `StarMade.jar`, `version.txt`, `lib/`, `native/`, `data/` —
     those come from the egg install so the game code stays current. Your `server-database/`,
     `blueprints/`, `server.cfg`, logs, etc. are copied.
4. You start the server from the panel.

The **source directory is only read** — never modified or deleted.

## Prerequisites

- Wings installed and the server's volume created (i.e. the egg install has run at least once).
- `rsync` (installed automatically on Debian/Ubuntu if missing).
- Run as root (needed to write into `/var/lib/pelican/volumes`).

## Manual alternative

If you prefer to do the copy yourself, create the server normally, stop it, then:

```bash
rsync -a --exclude StarMade.jar --exclude version.txt \
      --exclude lib/ --exclude native/ --exclude data/ \
      /path/to/old/starmade/ /var/lib/pelican/volumes/<uuid>/
chown -R <volume-owner> /var/lib/pelican/volumes/<uuid>
```

Find `<uuid>` under the server's **Manage** tab in the panel (or the create‑API response).
