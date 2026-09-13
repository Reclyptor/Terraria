#!/usr/bin/env bash
# Shared bats setup: source the toolkit shim and the adapter against a
# throwaway DATA_DIR. Tests that touch the network override http_get.
# shellcheck shell=bash
# shellcheck disable=SC2034

setup_adapter() {
    TEST_TMP=$(mktemp -d)
    export GAMEOPS_HOME=/opt/gameops
    export GAMEOPS_STATE="$TEST_TMP/state"
    export DATA_DIR="$TEST_TMP/data"
    export BACKUP_DIR="$TEST_TMP/backups"
    export GAME_ADAPTER=/opt/game/adapter.sh
    export LOG_LEVEL=warn
    export WORLD_SIZE=1
    mkdir -p "$GAMEOPS_STATE" "$DATA_DIR" "$BACKUP_DIR"

    export HTTP_LOG="$TEST_TMP/http.log"
    : > "$HTTP_LOG"

    # shellcheck source=/dev/null
    source "${GAMEOPS_HOME}/shim/adapter.sh"
    adapter_load
}

teardown_adapter() { rm -rf "$TEST_TMP"; }

fixture() { cat "/tests/fixtures/$1"; }

# Replace http_get with a stub: records the call, serves HTTP_STUB_FILE (to
# stdout or to the -o target) and exits HTTP_STUB_EXIT.
stub_http() {
    # shellcheck disable=SC2317,SC2329  # invoked by the adapter under test
    http_get() {
        printf '%s\n' "$*" >> "$HTTP_LOG"
        local out=""
        while (( $# )); do
            case "$1" in -o) out=$2; shift ;; esac
            shift
        done
        if [[ -n "${HTTP_STUB_FILE:-}" ]]; then
            if [[ -n "$out" ]]; then cat "$HTTP_STUB_FILE" > "$out"; else cat "$HTTP_STUB_FILE"; fi
        fi
        return "${HTTP_STUB_EXIT:-0}"
    }
}
