# The StarMade egg

`egg/egg-starmade.json` is a Pterodactyl `PTDL_v2` egg (the format Pelican imports natively).
It is **generated** from `egg-src/` — edit the sources and run `bash egg-src/build-egg.sh`, never
hand‑edit the JSON.

## Source layout (`egg-src/`)

| File | Role |
| --- | --- |
| `egg.base.json` | Metadata, docker images, config (`done`/`stop`), and the variable definitions. |
| `sm-download.sh` | Resolves a build from the CDN and extracts it into the current dir. Shared by install + AUTO_UPDATE. |
| `install.sh` | Install‑time script (runs in `/mnt/server`). Writes the helpers, then runs the downloader. Contains `__EMBED_*` markers. |
| `start.sh` | Runtime wrapper — the egg's startup command (`bash start.sh`). Syncs `server.cfg`, picks JVM args, execs the server. |
| `build-egg.sh` | Expands the `__EMBED_*` markers in `install.sh` with heredocs that write `sm-download.sh` + `start.sh`, then injects the result into `egg.base.json`. Output is fully self‑contained. |

## How it runs

**Install** (container `ghcr.io/pelican-eggs/installers:debian`): writes `start.sh` +
`sm-download.sh` into the server directory, then downloads and unzips the chosen StarMade build.

**Runtime** (`bash start.sh` in a `yolks` Java image):

1. Optional `AUTO_UPDATE` re‑pull of the latest build.
2. Sync `server.cfg` from panel variables (see below).
3. Detect the container's Java major version; for Java 9+ add the StarLoader agent + three
   `--add-opens`. Compute heap from `SERVER_MEMORY − HEAP_HEADROOM_MB`.
4. `exec java … -jar StarMade.jar -server -port:$SERVER_PORT`.

## Launch command (authoritative)

Verified against StarMade's `Starter.java` and a live boot:

```
java -javaagent:StarMade.jar \
     --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED \
     --add-opens=java.base/java.nio=ALL-UNNAMED \
     --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
     -Xms512M -Xmx<mem>M -jar StarMade.jar -server -port:<PORT>
```

- `-javaagent:StarMade.jar` — StarLoader `Premain-Class`. Required on modern builds.
- The three `--add-opens` — required for Java 21 reflection.
- `-port:<n>` is **colon form**. There is no port key in `server.cfg`, so this flag is the only
  way to change the port (default 4242).
- `-force` is a **client** flag and is intentionally *not* used for the server.

## Config sync

StarMade's `server.cfg` is `KEY = value // comment`. On boot `start.sh` sets a managed key by
rewriting the line (or appending it); StarMade then fills in all remaining defaults on first save.

| Panel variable | `server.cfg` key |
| --- | --- |
| `SERVER_NAME` | `SERVER_LIST_NAME` |
| `SERVER_DESCRIPTION` | `SERVER_LIST_DESCRIPTION` |
| `SERVER_HOSTNAME` | `HOST_NAME_TO_ANNOUNCE_TO_SERVER_LIST` |
| `MAX_CLIENTS` | `MAX_CLIENTS` |
| `ANNOUNCE_SERVER_TO_SERVERLIST` | `ANNOUNCE_SERVER_TO_SERVERLIST` |
| `USE_STARMADE_AUTHENTICATION` | `USE_STARMADE_AUTHENTICATION` |
| `REQUIRE_STARMADE_AUTHENTICATION` | `REQUIRE_STARMADE_AUTHENTICATION` |
| `USE_WHITELIST` | `USE_WHITELIST` |
| `SUPER_ADMIN_PASSWORD` | `SUPER_ADMIN_PASSWORD` (+ `SUPER_ADMIN_PASSWORD_USE`) |

> There is **no** `SERVER_NAME` key in StarMade — unknown keys are silently dropped when the
> game rewrites `server.cfg`. That's why the display name maps to `SERVER_LIST_NAME`.

### Setting any of the ~210 options

Add a panel variable whose env name is `SMCFG_<KEY>` and `start.sh` writes `<KEY> = value`.
Examples: `SMCFG_SECTOR_SIZE`, `SMCFG_ENEMY_SPAWNING`, `SMCFG_SERVER_LIST_DESCRIPTION`.

## Other variables

- `STARMADE_BRANCH` — `release` / `dev` / `pre` / `archive`.
- `STARMADE_VERSION` — a version like `0.304.7`, or `latest`.
- `AUTO_UPDATE` — re‑pull latest on each boot (`0`/`1`).
- `HEAP_HEADROOM_MB` — memory held back from `-Xmx` for the JVM's off‑heap/direct buffers
  (StarMade uses a lot). Raise if the container is OOM‑killed under load.
- `EXTRA_JVM_ARGS` — appended verbatim (e.g. `-XX:+UseG1GC -XX:MaxDirectMemorySize=2G`).

## Docker images

- `ghcr.io/pterodactyl/yolks:java_21` (default) — StarMade 0.3xx+.
- `ghcr.io/pterodactyl/yolks:java_8` — legacy < 0.3 worlds only.

`start.sh` adds the StarLoader agent + `--add-opens` only on Java 9+, so it does the right thing
for either image.
