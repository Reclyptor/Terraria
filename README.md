# Terraria

A self-contained **vanilla** Terraria dedicated server image — always the newest official
release — with scheduled backups, in-place auto-updates that warn players first, Discord
notifications, player join/leave events and configuration from the environment. Built on the
[GameOps](https://github.com/Reclyptor/GameOps) toolkit.

```sh
mkdir -p data backups && sudo chown -R 1000:1000 data backups
docker run -d --name terraria -p 7777:7777 \
  -e SERVER_NAME=Terraria -e WORLD_NAME=world -e WORLD_SIZE=2 -e GAME_PASSWORD=secret \
  -e DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/… \
  -v "$PWD/data:/data" -v "$PWD/backups:/backups" \
  ghcr.io/reclyptor/terraria:latest
```

Or use [`compose.yaml`](compose.yaml). A world is generated on first start (a large one takes a
few minutes); an existing `.wld` in `/data/worlds` with the same name is loaded instead.

## What it does for you

| | |
|---|---|
| **Backups** | Nightly by default: console `save`, then `worlds/` and `banlist.txt` into `/backups/terraria-<timestamp>.tar.gz`, pruned after `BACKUP_RETAIN_DAYS`. `docker exec terraria gameops backup` any time. |
| **Updates** | Hourly check of terraria.org's release list. When a new server lands: players are warned in-game at 15/10/5/2/1 min, a backup is taken, the world is saved, the bundle is verified and installed, and the server relaunches **inside the same container**. |
| **Notifications** | Discord: online, offline, crashed, updating/updated, backup, join, leave. Plain text, every message overridable. |
| **Console** | `docker exec terraria gameops console <command>` types at the server: `say`, `kick`, `ban`, `settle`, `dawn`, … |
| **Lifecycle** | Graceful stop on `SIGTERM` (console `exit`, which saves). Crashes exit the container with the game's code. Health is process + ready — **never a port probe**, see below. |

The vanilla server has no RCON or API; everything above works through the console the toolkit
attaches to its stdin.

## Configuration

### Terraria

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_NAME` | `Terraria` | The name notifications use. The vanilla server has no listing name of its own. |
| `MAX_PLAYERS` | `8` | |
| `GAME_PASSWORD` | — | Join password. |
| `MOTD` | — | Message of the day. |
| `WORLD_NAME` | `world` | World name; the file is `/data/worlds/<name>.wld`. |
| `WORLD_SEED` | — | World seed (first generation only). |
| `WORLD_SIZE` | `2` | `1` small, `2` medium, `3` large. Used only when the world is generated. |
| `DIFFICULTY` | `0` | `0` classic, `1` expert, `2` master, `3` journey (first generation only). |
| `SECURE` | `1` | Anti-cheat protection. |
| `LANGUAGE` | `en-US` | |
| `NPCSTREAM` | `60` | NPC update rate. |
| `PRIORITY` | `1` | Process priority hint. |
| `PORT` | `7777` | Game port (TCP). The toolkit's TCP gate listens here (`GATE_ENABLED=true`, `GATE_EXPECT=Terraria`); the game itself listens on `GATE_TARGET_PORT` (`7778`) on loopback. |

**The environment is the source of truth** for `serverconfig.txt`, which is rendered on every
start. The ban list is the game's own and is kept.

### Backups, updates, notifications

These are the [GameOps](https://github.com/Reclyptor/GameOps#configuration) variables and are
identical across every Reclyptor game image: `BACKUP_CRON`, `BACKUP_RETAIN_DAYS`,
`BACKUP_ON_UPDATE`, `UPDATE_CRON`, `UPDATE_ON_BOOT`, `UPDATE_WARN_MINUTES`,
`UPDATE_SKIP_IF_PLAYERS`, `STOP_TIMEOUT`, `METRICS_PORT`, `DISCORD_WEBHOOK_URL`,
`DISCORD_<EVENT>_MESSAGE`, `TZ`, … Backups are verified as they are written; `gameops backup list`,
`gameops backup verify latest` and `gameops restore latest` work from `docker exec`.

## Volumes and ports

| | |
|---|---|
| `/data` | `worlds/ logs/ serverconfig.txt banlist.txt` — uid/gid **1000** |
| `/backups` | Archives. Mount a NAS share here for off-box copies. |
| `7777/tcp` | Game, behind the toolkit's TCP gate: a client is forwarded to the server only after it sends a Terraria connect request, so port scans and half-open connections — which crash the vanilla server (`ObjectDisposedException` in `Netplay`) — never reach it. Probes still belong on `GET /healthz` (9110), not here. |
| `9110/tcp` | `/metrics` (Prometheus) and `/healthz` — `METRICS_PORT`, `0` disables |

## Development

```sh
tests/run.sh      # bats, inside the built image
tests/smoke.sh    # real server: older release → update in place → console → backup → SIGTERM save
                  # SMOKE_OLD_RELEASE picks the starting release (default 1456)
```

## License

MIT.
