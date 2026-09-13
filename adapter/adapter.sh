#!/usr/bin/env bash
# GameOps adapter for the vanilla Terraria dedicated server.
# Contract: https://github.com/Reclyptor/GameOps/blob/master/docs/CONTRACT.md
#
# The server has no RCON and no API: everything goes through the console FIFO
# the toolkit attaches to its stdin, and replies are read back from the
# console log.
# shellcheck shell=bash
# shellcheck disable=SC2034  # GAME_* and GAME_CMD are consumed by the toolkit

GAME_NAME=terraria
GAME_DIR=${GAME_DIR:-/opt/terraria}
GAME_PORT=${PORT:-7777}
GAME_PORT_PROTO=tcp

ADAPTER_DIR=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=adapter/lib/install.sh
source "${ADAPTER_DIR}/lib/install.sh"
# shellcheck source=adapter/lib/settings.sh
source "${ADAPTER_DIR}/lib/settings.sh"

WORLDS_DIR="${DATA_DIR}/worlds"
CONFIG_FILE="${DATA_DIR}/serverconfig.txt"

# ── install / version / update ──────────────────────────────────────────────

game_install() {
    mkdir -p "$WORLDS_DIR" "${DATA_DIR}/logs"
    [[ -f "${DATA_DIR}/banlist.txt" ]] || : > "${DATA_DIR}/banlist.txt"
    # The server insists on a favorites.json under its "My Games" dir; without
    # one it logs an error on every start.
    local d
    for d in "${HOME:-$DATA_DIR}/My Games/Terraria" "${HOME:-$DATA_DIR}/.local/share/Terraria"; do
        mkdir -p "$d"
        [[ -f "${d}/favorites.json" ]] || echo '{}' > "${d}/favorites.json"
    done
    terraria_render_config "${ADAPTER_DIR}/templates/serverconfig.txt" "$CONFIG_FILE"
}

game_version() { terraria_release_to_version "$(terraria_installed_release)"; }

game_update_available() {
    local json latest current
    json=$(http_get "$RELEASES_API") || { log_warn "terraria.org release list unreachable"; return 1; }
    latest=$(terraria_latest_from_json "$json")
    [[ -n "$latest" ]] || { log_warn "terraria.org release list had no server zips"; return 1; }
    current=$(terraria_installed_release)
    (( latest > current )) || return 1
    printf '%s' "$latest"
}

game_update_apply() { terraria_install_release "$1"; }

# ── process ─────────────────────────────────────────────────────────────────

# The TerrariaServer wrapper only sets MONO_IOMAP (already in the environment)
# and execs the binary; running the binary directly keeps it the recorded pid.
game_start_cmd() {
    GAME_CMD=("${GAME_DIR}/TerrariaServer.bin.x86_64" -config "$CONFIG_FILE" -logpath "${DATA_DIR}/logs")
}

# NEVER probe the port. A TCP connection that opens and closes without a
# handshake trips a race in Terraria's Netplay.UpdateConnectedClients
# (ObjectDisposedException on the client's NetworkStream) and kills the server
# with exit 1 — intermittently, which is worse. Readiness comes from the
# console instead, and the health check below deliberately avoids the port.
game_ready() { grep -c 'Server started' "$GAME_LOG" >/dev/null 2>&1; }

game_healthy() {
    server_pid >/dev/null || { echo "unhealthy: server process not running" >&2; return 1; }
    flag_is_set ready       || { echo "unhealthy: server not ready" >&2; return 1; }
    return 0
}

# `exit` saves the world and stops the server.
game_shutdown() { console_send exit; }

# ── control (console) ───────────────────────────────────────────────────────

# `save` returns at once while the world is still being written; wait for the
# file to settle so a backup taken right after archives a complete world.
game_save() {
    console_send save || return 1
    sleep 1
    wait_settled "${WORLDS_DIR}/${WORLD_NAME:-world}.wld" 3 120
}
game_broadcast() { console_send "say $*"; }

# Send a console command and return the lines the server printed in reply.
#   terraria_console_query <command> [seconds]
terraria_console_query() {
    local cmd=$1 wait=${2:-2} offset
    offset=$(stat -c %s "$GAME_LOG" 2>/dev/null || echo 0)
    console_send "$cmd" || return 1
    sleep "$wait"
    tail -c "+$(( offset + 1 ))" "$GAME_LOG"
}

# Reply to `playing`:
#   No players connected.
# or one "<name> (<ip>:<port>)" line per player.
terraria_parse_player_count() {
    local n
    n=$(printf '%s\n' "$1" | grep -cE '^.+ \([0-9a-fA-F:.]+\)$' || true)
    printf '%s' "${n:-0}"
}

game_players() {
    local out
    out=$(terraria_console_query playing 2) || return 1
    terraria_parse_player_count "$out"
}

# ── events ──────────────────────────────────────────────────────────────────

# Console lines, usually echoed behind the server's ": " prompt:
#   : Alice has joined.
#   : Alice has left.
terraria_parse_events() {
    sed -un \
        -e 's/^\(: \)\{0,1\}\(.*\) has joined\.$/JOIN \2/p' \
        -e 's/^\(: \)\{0,1\}\(.*\) has left\.$/LEAVE \2/p'
}

game_events() { follow_log | terraria_parse_events; }

# ── backups ─────────────────────────────────────────────────────────────────

game_backup_paths() { printf '%s\n' worlds banlist.txt; }
