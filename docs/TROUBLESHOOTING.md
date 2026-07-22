# Troubleshooting

### Server console shows a native library / `UnsatisfiedLinkError` crash at startup
StarMade's natives are **x86‑64 only**. This happens on an ARM host (or an arm64 container).
Run on an x86‑64 host, or select an amd64 node. There is no ARM build of `libStarMadeNative`.

### Server stays "Starting" forever in the panel
Wings marks a server online when it sees the console line `now waiting for connections`. If you
customized the egg's startup detection, restore `config.startup.done` to `now waiting for
connections`. Check the console for an earlier crash (Java, natives, out of memory).

### Container is OOM‑killed under load
StarMade uses a lot of off‑heap/direct memory. `-Xmx` is set to `SERVER_MEMORY − HEAP_HEADROOM_MB`.
Raise **Heap Headroom (MB)** (default 1024) or increase the server's memory limit.

### A `server.cfg` setting I changed reverts / does nothing
Only real StarMade keys persist — the game drops unknown keys when it rewrites `server.cfg`.
The display name is `SERVER_LIST_NAME`, not `SERVER_NAME`. Set arbitrary keys with a panel
variable named `SMCFG_<KEY>` (e.g. `SMCFG_SECTOR_SIZE`). See [EGG.md](EGG.md).

### Public server list shows nothing
`ANNOUNCE_SERVER_TO_SERVERLIST` needs a reachable hostname. Set **Announce Hostname**
(`HOST_NAME_TO_ANNOUNCE_TO_SERVER_LIST`) to your public IP/DNS.

### `/shutdown` / Stop takes a moment
That's expected — `/shutdown 10` runs a countdown and a full world save before exiting. The
console prints `ServerState saved!` when done.

### Download fails during install
The build comes from `files.star-made.org` (index) + `files-origin.star-made.org` (zip). Check
the container has outbound HTTP, and that `STARMADE_BRANCH` is one of release/dev/pre/archive.
An invalid `STARMADE_VERSION` falls back to the latest build on that branch.

### `setup.sh` provisioning: "No free allocation"
Create an allocation for the game port under **Admin → Nodes → your node → Allocations**, then
re‑run provisioning.

### `setup.sh` provisioning: auth failed (HTTP 401/403)
Use an **Application** API key (Admin → API Keys), not a client/account key, and make sure it has
read/write.

### Legacy (pre‑0.3) world needs Java 8
Switch the server's Docker image to `ghcr.io/pterodactyl/yolks:java_8` and set `STARMADE_VERSION`
to a `< 0.3` build. `start.sh` omits the StarLoader agent + `--add-opens` automatically on Java 8.
