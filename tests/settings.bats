#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "renders serverconfig.txt from the environment" {
    export GATE_ENABLED=false   # the image turns the gate on; this test covers the plain layout
    export WORLD_NAME=Ember WORLD_SIZE=3 WORLD_SEED=abc DIFFICULTY=2 \
           MAX_PLAYERS=16 GAME_PASSWORD=example-pass MOTD="Welcome" LANGUAGE=de-DE
    terraria_render_config /opt/game/templates/serverconfig.txt "$TEST_TMP/c.txt"
    grep -qx "world=${DATA_DIR}/worlds/Ember.wld" "$TEST_TMP/c.txt"
    grep -qx "worldpath=${DATA_DIR}/worlds" "$TEST_TMP/c.txt"
    grep -qx "autocreate=3" "$TEST_TMP/c.txt"
    grep -qx "worldname=Ember" "$TEST_TMP/c.txt"
    grep -qx "seed=abc" "$TEST_TMP/c.txt"
    grep -qx "difficulty=2" "$TEST_TMP/c.txt"
    grep -qx "maxplayers=16" "$TEST_TMP/c.txt"
    grep -qx "port=7777" "$TEST_TMP/c.txt"
    grep -qx "ip=0.0.0.0" "$TEST_TMP/c.txt"
    grep -qx "password=example-pass" "$TEST_TMP/c.txt"
    grep -qx "motd=Welcome" "$TEST_TMP/c.txt"
    grep -qx "language=de-DE" "$TEST_TMP/c.txt"
    grep -qx "banlist=${DATA_DIR}/banlist.txt" "$TEST_TMP/c.txt"
    ! grep -q '@' "$TEST_TMP/c.txt"
}

@test "defaults are vanilla when nothing is set" {
    unset WORLD_NAME WORLD_SIZE WORLD_SEED DIFFICULTY MAX_PLAYERS GAME_PASSWORD MOTD
    terraria_render_config /opt/game/templates/serverconfig.txt "$TEST_TMP/c.txt"
    grep -qx "world=${DATA_DIR}/worlds/world.wld" "$TEST_TMP/c.txt"
    grep -qx "autocreate=2" "$TEST_TMP/c.txt"
    grep -qx "difficulty=0" "$TEST_TMP/c.txt"
    grep -qx "maxplayers=8" "$TEST_TMP/c.txt"
    grep -qx "password=" "$TEST_TMP/c.txt"
    grep -qx "secure=1" "$TEST_TMP/c.txt"
}

@test "game_install lays out the data dir and renders the config" {
    game_install
    [ -d "$DATA_DIR/worlds" ]
    [ -f "$DATA_DIR/banlist.txt" ]
    [ -f "$DATA_DIR/serverconfig.txt" ]
    [ -f "$HOME/My Games/Terraria/favorites.json" ]
    grep -qx "worldname=world" "$DATA_DIR/serverconfig.txt"
}

@test "game_install never clobbers the ban list" {
    mkdir -p "$DATA_DIR"; echo "griefer" > "$DATA_DIR/banlist.txt"
    game_install
    [ "$(cat "$DATA_DIR/banlist.txt")" = griefer ]
}

@test "start command runs the binary directly with the rendered config" {
    game_start_cmd
    [ "${GAME_CMD[0]}" = /opt/terraria/TerrariaServer.bin.x86_64 ]
    [[ " ${GAME_CMD[*]} " == *" -config ${DATA_DIR}/serverconfig.txt "* ]]
    [[ " ${GAME_CMD[*]} " == *" -logpath ${DATA_DIR}/logs"* ]]
}

@test "backup paths" {
    [ "$(game_backup_paths | tr '\n' ' ')" = "worlds banlist.txt " ]
}

@test "with the gate on, the game binds loopback on the gate's target port" {
    export GATE_ENABLED=true GATE_TARGET_PORT=7778
    terraria_render_config /opt/game/templates/serverconfig.txt "$TEST_TMP/c.txt"
    grep -qx "port=7778" "$TEST_TMP/c.txt"
    grep -qx "ip=127.0.0.1" "$TEST_TMP/c.txt"
}

@test "readiness comes from the console log, never the port" {
    export GAME_LOG="$TEST_TMP/console.log"
    printf 'Listening on port 7777\n' > "$GAME_LOG"
    ! game_ready
    printf ': Server started\n' >> "$GAME_LOG"
    game_ready
    ! grep -q tcp_port_open <(declare -f game_ready game_healthy)
}
