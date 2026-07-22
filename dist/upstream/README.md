# Upstream copy — for the public `pelican-eggs/eggs` repo

`egg-starmade.json` here is a **PR-ready variant** of our canonical egg
([`../../egg/egg-starmade.json`](../../egg/egg-starmade.json)), meant to replace the
outdated public egg at
[`pelican-eggs/eggs` → `game_eggs/starmade/egg-starmade.json`](https://github.com/pelican-eggs/eggs/blob/master/game_eggs/starmade/egg-starmade.json).

It is **generated** — after changing the canonical egg, regenerate with:

```bash
bash egg-src/build-egg.sh          # rebuild the canonical egg first
# then re-run the transform used to make this file (see repo history), or hand-apply:
#   meta.update_url -> null, fresh uuid, docker_images -> ghcr.io/pelican-eggs/yolks
```

## How it differs from our canonical egg (and why)

| Field | Ours | Upstream copy | Reason |
| --- | --- | --- | --- |
| `meta.update_url` | our raw GitHub URL | `null` | Don't point every upstream user's "Update Egg" at our repo. |
| `uuid` | our stable UUID | a **fresh** UUID | So panels holding both eggs don't treat them as the same egg. |
| `docker_images` | `ghcr.io/pterodactyl/yolks` | `ghcr.io/pelican-eggs/yolks` | Match the pelican-eggs repo's own image convention. |

Everything else (the install/download logic, the StarLoader `-javaagent` + `--add-opens`
launch, `server.cfg` sync, ready/stop lines) is identical.

## Submitting the PR

1. Fork `pelican-eggs/eggs`.
2. Replace `game_eggs/starmade/egg-starmade.json` with this file's contents.
3. Refresh the folder's `README.md` if it still describes the old `StarMade-Starter.jar` flow.
4. Open a PR describing why: the current public egg uses Java 16 and omits the StarLoader
   agent + `--add-opens`, so it can't start modern (0.3xx / Java 21) builds.
