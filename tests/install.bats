#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; stub_http; }
teardown() { teardown_adapter; }

@test "release numbers become dotted versions" {
    [ "$(terraria_release_to_version 1458)" = 1.4.5.8 ]
    [ "$(terraria_release_to_version 1449)" = 1.4.4.9 ]
}

@test "the installed server reports its version" {
    [ "$(terraria_installed_release)" = 1458 ]
    [ "$(game_version)" = 1.4.5.8 ]
}

@test "picks the highest release from the API list" {
    [ "$(terraria_latest_from_json "$(fixture servers.json)")" = 1458 ]
    [ -z "$(terraria_latest_from_json '[]')" ]
    [ -z "$(terraria_latest_from_json '["unrelated.zip"]')" ]
}

@test "update available only when the API is ahead" {
    export HTTP_STUB_FILE=/tests/fixtures/servers.json
    run game_update_available
    [ "$status" -eq 1 ]
    export GAME_DIR="$TEST_TMP/old"; mkdir -p "$GAME_DIR"; echo 1456 > "$GAME_DIR/VERSION"
    run game_update_available
    [ "$status" -eq 0 ]
    [ "$output" = 1458 ]
}

@test "an unreachable release list is reported as current" {
    export HTTP_STUB_EXIT=1
    run game_update_available
    [ "$status" -eq 1 ]
}

@test "a corrupt download never touches the installation" {
    export GAME_DIR="$TEST_TMP/game"
    mkdir -p "$GAME_DIR"; echo keep > "$GAME_DIR/TerrariaServer.bin.x86_64"; echo 1456 > "$GAME_DIR/VERSION"
    echo "not a zip" > "$TEST_TMP/bad.zip"
    export HTTP_STUB_FILE="$TEST_TMP/bad.zip"
    run terraria_install_release 1458
    [ "$status" -eq 1 ]
    [ "$(cat "$GAME_DIR/TerrariaServer.bin.x86_64")" = keep ]
    [ "$(cat "$GAME_DIR/VERSION")" = 1456 ]
}

@test "a real archive replaces the installation and records the release" {
    export GAME_DIR="$TEST_TMP/game"
    mkdir -p "$GAME_DIR"; echo old > "$GAME_DIR/stale.dll"; echo 1456 > "$GAME_DIR/VERSION"
    mkdir -p "$TEST_TMP/src/9999/Linux" "$TEST_TMP/src/9999/Windows"
    echo new > "$TEST_TMP/src/9999/Linux/TerrariaServer.bin.x86_64"; echo wrap > "$TEST_TMP/src/9999/Linux/TerrariaServer"
    echo cfg > "$TEST_TMP/src/9999/Windows/serverconfig.txt"
    (cd "$TEST_TMP/src" && python3 -c "
import zipfile,os
z=zipfile.ZipFile('../good.zip','w')
for r,d,f in os.walk('9999'):
    for n in f: z.write(os.path.join(r,n))
z.close()")
    export HTTP_STUB_FILE="$TEST_TMP/good.zip"
    terraria_install_release 9999
    [ "$(cat "$GAME_DIR/VERSION")" = 9999 ]
    [ "$(cat "$GAME_DIR/TerrariaServer.bin.x86_64")" = new ]
    [ ! -e "$GAME_DIR/stale.dll" ]
    [ -x "$GAME_DIR/TerrariaServer.bin.x86_64" ]
}
