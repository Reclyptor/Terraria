#!/usr/bin/env bats
load test_helper

setup()    { setup_adapter; }
teardown() { teardown_adapter; }

@test "console lines become JOIN/LEAVE events and nothing else" {
    run terraria_parse_events < /tests/fixtures/console.log
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "JOIN Alice" ]
    [ "${lines[1]}" = "JOIN Bob Builder" ]
    [ "${lines[2]}" = "JOIN Carol" ]
    [ "${lines[3]}" = "LEAVE Alice" ]
    [ "${lines[4]}" = "LEAVE Bob Builder" ]
    [ "${lines[5]}" = "LEAVE Carol" ]
    [ "${#lines[@]}" -eq 6 ]
}

@test "playing output parses to a count" {
    [ "$(terraria_parse_player_count "$(fixture playing-none.txt)")" = 0 ]
    [ "$(terraria_parse_player_count "$(fixture playing-two.txt)")" = 2 ]
    [ "$(terraria_parse_player_count '')" = 0 ]
}

@test "console queries read the reply from the console log" {
    export GAME_LOG="$TEST_TMP/console.log"
    printf 'old line\n' > "$GAME_LOG"
    console_send() { printf '%s reply\n' "$1" >> "$GAME_LOG"; }
    [ "$(terraria_console_query playing 0)" = "playing reply" ]
}
