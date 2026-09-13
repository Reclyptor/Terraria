#!/usr/bin/env bash
# Render serverconfig.txt from the environment.
# shellcheck shell=bash

# terraria_render_config <template> <destination>
# Every placeholder has a default; an unset variable leaves the vanilla value.
# With the toolkit's TCP gate on (the image default), the game listens on the
# gate's loopback target port and only the gate is reachable on PORT.
terraria_render_config() {
    local template=$1 dest=$2
    local name=${WORLD_NAME:-world}
    local worlds="${DATA_DIR}/worlds"
    local port=${GAME_PORT:-7777} bind=0.0.0.0
    if is_true "${GATE_ENABLED:-false}"; then
        port=${GATE_TARGET_PORT:?GATE_ENABLED needs GATE_TARGET_PORT}
        bind=127.0.0.1
    fi
    sed \
        -e "s|@WORLD_FILE@|${worlds}/${name}.wld|" \
        -e "s|@WORLD_PATH@|${worlds}|" \
        -e "s|@WORLD_SIZE@|${WORLD_SIZE:-2}|" \
        -e "s|@WORLD_NAME@|${name}|" \
        -e "s|@SEED@|${WORLD_SEED:-}|" \
        -e "s|@DIFFICULTY@|${DIFFICULTY:-0}|" \
        -e "s|@MAX_PLAYERS@|${MAX_PLAYERS:-8}|" \
        -e "s|@PORT@|${port}|" \
        -e "s|@BIND@|${bind}|" \
        -e "s|@PASSWORD@|${GAME_PASSWORD:-}|" \
        -e "s|@MOTD@|${MOTD:-}|" \
        -e "s|@BANLIST@|${DATA_DIR}/banlist.txt|" \
        -e "s|@SECURE@|${SECURE:-1}|" \
        -e "s|@LANGUAGE@|${LANGUAGE:-en-US}|" \
        -e "s|@NPCSTREAM@|${NPCSTREAM:-60}|" \
        -e "s|@PRIORITY@|${PRIORITY:-1}|" \
        "$template" > "${dest}.tmp" && mv "${dest}.tmp" "$dest"
}
