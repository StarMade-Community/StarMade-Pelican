# StarMade × Pelican

A modern [Pelican Panel](https://pelican.dev) setup for hosting a **StarMade** dedicated
server: a fresh, self‑contained egg plus an interactive installer that can stand up Pelican
Panel + Wings on a bare server, provision your StarMade server through the Pelican API, and
migrate an existing StarMade Docker setup (world data included).

The public StarMade eggs floating around are years out of date — wrong download URLs, Java 8
only, and missing the StarLoader agent + module‑open JVM args that modern (0.3xx / Java 21)
builds require and refuse to start without. This egg is built and **verified against the
current StarMade launcher source and the live CDN**.

> **Host requirement:** StarMade ships **x86‑64 (amd64) natives only** — there are no ARM
> builds of `libStarMadeNative`. Run this on an x86‑64 Linux host. (It also runs on Apple
> Silicon only under amd64 emulation.)

## Quick start

```bash
git clone https://github.com/StarMade-Community/StarMade-Pelican.git
cd StarMade-Pelican
./setup.sh
```

`setup.sh` is a menu:

| Option | What it does |
| --- | --- |
| **Full setup** | Installs Docker + Pelican Panel + Wings **if missing**, then provisions a StarMade server. Idempotent — skips anything already present. |
| **Prereqs only** | Just Docker + Panel + Wings. |
| **Provision a server** | You already run Pelican — create/configure a StarMade server via the API. |
| **Migrate a Docker setup** | Import an existing StarMade `docker-compose`/`.env` + world data into a Pelican server. |
| **Egg import help / rebuild** | Where the egg is and how to import it. |

Non‑interactive: `./setup.sh --yes --answers answers.env` (see [`templates/answers.env.example`](templates/answers.env.example)).

## The egg

The importable egg is [`egg/egg-starmade.json`](egg/egg-starmade.json). Import it once in the
panel (**Admin → Eggs → Import → From File/URL**) — there is no public API to import eggs, so
this one step is manual. After that, `setup.sh` finds it by name and provisions servers against it.

What makes it correct for modern StarMade:

- **Download:** resolves the build from `files.star-made.org/<branch>buildindex` and pulls the
  single build zip from `files-origin.star-made.org` — release / dev / pre / archive branch, any
  version or `latest`.
- **Launch** (verified end‑to‑end in the `yolks:java_21` container):
  ```
  java -javaagent:StarMade.jar \
       --add-opens=java.base/jdk.internal.ref=ALL-UNNAMED \
       --add-opens=java.base/java.nio=ALL-UNNAMED \
       --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
       -Xms512M -Xmx<mem-headroom>M -jar StarMade.jar -server -port:<PORT>
  ```
  The `-javaagent` is StarLoader's premain — omit it and modern builds don't start.
- **Config:** panel variables are written into `server.cfg` on boot (e.g. `SERVER_LIST_NAME`,
  `MAX_CLIENTS`, authentication, whitelist, super‑admin password). Any of StarMade's ~210
  settings can be set by adding a panel variable named `SMCFG_<KEY>`.
- **Ready/stop:** Wings marks the server online on `now waiting for connections`; the stop
  command `/shutdown 10` triggers a clean, world‑saving shutdown.

Edit the egg via [`egg-src/`](egg-src/) (the `.sh` files are the source of truth) and rebuild:

```bash
bash egg-src/build-egg.sh      # regenerates egg/egg-starmade.json
```

## Docs

- [docs/INSTALL.md](docs/INSTALL.md) — full turnkey install walkthrough
- [docs/EGG.md](docs/EGG.md) — egg internals, variables, and how it's built
- [docs/IMPORT.md](docs/IMPORT.md) — migrating an existing Docker/native server
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — common issues

## Repo layout

```
egg/egg-starmade.json   generated, importable egg
egg-src/                egg source of truth (install.sh, start.sh, sm-download.sh, build-egg.sh)
setup.sh                interactive installer / provisioner
lib/                    common.sh, prereqs.sh, pelican-api.sh, import-docker.sh
templates/              panel compose, answers file
docs/                   guides
```

## Verification status

The **egg runtime** is verified end‑to‑end: install → correct JVM args → StarLoader agent →
`server.cfg` sync → world generation → `now waiting for connections` → `/shutdown` clean save,
in a `linux/amd64` `ghcr.io/pterodactyl/yolks:java_21` container. The **Panel/Wings turnkey
install** is syntax‑checked and logic‑reviewed; run it on your target x86‑64 Linux host to
validate against your environment.
