#!/usr/bin/env bash
# End-to-end against the real server. The install directory lives in a volume
# seeded with an OLDER release, so the first thing proven is the in-place
# update to the newest one (real download, real relaunch, same container, the
# old release's world carried across). Then: console broadcast → player query
# → backup → live update check → `exit` on SIGTERM saves the world. Webhooks
# go to a receiver in a sidecar container.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GAME_IMAGE:=terraria:test}"
: "${SMOKE_OLD_RELEASE:=1456}"
runner="${GAME_IMAGE}-runner"
name=terraria-smoke-$$
net="${name}-net"
vol="${name}-install"
hooks_ctr="${name}-hooks"
hook_port=18089
work=$(mktemp -d)
hooks="$work/webhooks.log"

cleanup() {
    docker rm -f "$name" "$hooks_ctr" >/dev/null 2>&1 || true
    docker network rm "$net" >/dev/null 2>&1 || true
    docker volume rm "$vol" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

fail() {
    echo "SMOKE FAIL: $*" >&2
    echo "--- container log (progress lines dropped) ---" >&2
    docker logs "$name" 2>&1 | grep -vE '[0-9]+(\.[0-9]+)?%' | tail -60 >&2 || true
    echo "--- server log files ---" >&2
    docker run --rm --volumes-from "$name" --entrypoint bash "$GAME_IMAGE" -c 'for f in /data/logs/*.log; do echo "## $f"; tail -60 "$f"; done' 2>&1 >&2 || true
    echo "--- webhooks ---" >&2; sync_hooks; cat "$hooks" >&2
    exit 1
}
step() { echo "==> $*"; }
sync_hooks() { docker logs "$hooks_ctr" 2>/dev/null > "$hooks" || true; }
wait_for() {
    local what=$1 pattern=$2 timeout=${3:-60} i
    for (( i = 0; i < timeout; i++ )); do
        sync_hooks; grep -cE "$pattern" "$hooks" >/dev/null && return 0; sleep 1
    done
    fail "timed out waiting for ${what}: /${pattern}/"
}
wait_for_log() {
    local pattern=$1 timeout=${2:-60} want=${3:-1} i
    for (( i = 0; i < timeout; i++ )); do
        (( $(docker logs "$name" 2>&1 | grep -cE "$pattern") >= want )) && return 0; sleep 1
    done
    fail "timed out waiting for ${want}x log: /${pattern}/"
}
in_game() { docker exec "$name" bash -c "source /opt/gameops/shim/adapter.sh; adapter_load; $*"; }

step "build images"
[[ -n "$(docker images -q "$GAME_IMAGE")" ]] || docker build -q -t "$GAME_IMAGE" . >/dev/null
docker build -q -t "$runner" --build-arg "GAME_IMAGE=${GAME_IMAGE}" -f tests/runner.Dockerfile tests >/dev/null

step "start webhook receiver"
docker network create "$net" >/dev/null
docker run -d --name "$hooks_ctr" --network "$net" --entrypoint python3 "$runner" -u -c "
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        print(body, flush=True)
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('0.0.0.0', ${hook_port}), H).serve_forever()
" >/dev/null
sleep 1

step "install release ${SMOKE_OLD_RELEASE} into a volume (the update's starting point)"
# A fresh named volume is seeded from the image's /opt/terraria, ownership
# included; the adapter's own installer then replaces it with the old release.
docker volume create "$vol" >/dev/null
docker run --rm -v "$vol:/opt/terraria" --entrypoint bash "$GAME_IMAGE" \
    -c "source /opt/gameops/shim/adapter.sh; adapter_load; terraria_install_release ${SMOKE_OLD_RELEASE}" \
    || fail "could not install release ${SMOKE_OLD_RELEASE}"

step "run terraria ${SMOKE_OLD_RELEASE} (small world)"
docker run -d --name "$name" --network "$net" -v "$vol:/opt/terraria" \
    -e "DISCORD_WEBHOOK_URL=http://${hooks_ctr}:${hook_port}/hook" \
    -e SERVER_NAME=Smoke -e WORLD_NAME=smoke -e WORLD_SIZE=1 -e MOTD="smoke test" \
    -e UPDATE_ON_BOOT=false -e UPDATE_ENABLED=false -e UPDATE_WARN_MINUTES=0 \
    -e READY_TIMEOUT=900 -e STOP_TIMEOUT=120 -e BACKUP_RETAIN_DAYS=0 -e LOG_LEVEL=debug \
    "$GAME_IMAGE" >/dev/null
wait_for "START notification" 'Smoke server is online' 900
old_version=$(in_game "terraria_release_to_version ${SMOKE_OLD_RELEASE}")
[[ "$(in_game game_version)" == "$old_version" ]] || fail "expected ${old_version} installed, got $(in_game game_version)"

step "update in place to the newest release"
# shellcheck disable=SC2016  # expanded inside the container, on purpose
latest=$(in_game 'terraria_latest_from_json "$(http_get "$RELEASES_API")"')
[[ "$latest" =~ ^[0-9]+$ ]] || fail "could not read the newest release from terraria.org: '${latest}'"
(( latest > SMOKE_OLD_RELEASE )) || fail "SMOKE_OLD_RELEASE must be older than the newest release (${latest})"
latest_version=$(in_game "terraria_release_to_version ${latest}")
echo "    ${old_version} → ${latest_version}"
docker exec "$name" gameops update
wait_for "UPDATE_PRE notification" "Smoke server is updating to ${latest}" 30
wait_for "BACKUP_POST notification (pre-update)" 'Pre-update backup of the Smoke server complete: /backups/terraria-' 180
wait_for "UPDATE_POST notification" "Smoke server updated to ${latest_version}" 600
wait_for_log 'Smoke is ready' 600 2
[[ "$(docker inspect -f '{{.RestartCount}}' "$name")" == 0 ]] || fail "container restarted during the update"
[[ "$(docker inspect -f '{{.State.Running}}' "$name")" == true ]] || fail "container not running after the update"
[[ "$(in_game game_version)" == "$latest_version" ]] || fail "expected ${latest_version} after the update, got $(in_game game_version)"
[[ "$(docker exec "$name" cat /opt/terraria/VERSION)" == "$latest" ]] || fail "VERSION file not updated"
docker exec "$name" grep -c 'worldname=smoke' /data/serverconfig.txt >/dev/null || fail "serverconfig.txt lost across the update"

step "health, console broadcast, player query"
for i in $(seq 1 12); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]] && break
    sleep 5
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' "$name")" == healthy ]] || fail "container health is $(docker inspect -f '{{.State.Health.Status}}' "$name")"
in_game 'game_broadcast hello from smoke'
wait_for_log 'hello from smoke' 15
[[ "$(in_game 'game_players')" == 0 ]] || fail "expected 0 players"
docker exec "$name" grep -c 'worldname=smoke' /data/serverconfig.txt >/dev/null || fail "serverconfig.txt not rendered"
docker exec "$name" test -f /data/worlds/smoke.wld || fail "world file not generated"

step "backup"
docker exec "$name" gameops backup
[[ "$(docker exec "$name" gameops backup list | wc -l)" == 2 ]] || fail "expected the pre-update archive and this one"
archive=$(docker exec "$name" gameops backup list | head -1 | cut -f1)
docker exec "$name" gameops backup verify "$archive" | grep -q '^OK' || fail "backup verify failed"
docker exec "$name" tar -tzf "$archive" | grep -c '^worlds/smoke.wld$' >/dev/null || fail "archive lacks worlds/smoke.wld"

step "update check against the live release list"
out=$(in_game 'game_update_available; echo "rc=$?"')
[[ "$out" == *"rc=1"* ]] || fail "just updated, so the check must report current: ${out}"

step "the gate absorbs the crash trigger: 40 bare connects, half-open connections, a junk request"
docker exec "$name" grep -qx 'ip=127.0.0.1' /data/serverconfig.txt || fail "the game should bind loopback behind the gate"
docker exec "$name" grep -qx 'port=7778' /data/serverconfig.txt || fail "the game should listen on the gate's target port"
# Run the abuse from the runner container on the private network, straight at the public port.
docker run -i --rm --network "$net" --entrypoint python3 "$runner" - "$name" <<'PY'
import socket, sys, time
host = sys.argv[1]
for i in range(40):                       # open-and-drop, the exact crash trigger
    s = socket.create_connection((host, 7777), timeout=5); s.close()
half = [socket.create_connection((host, 7777), timeout=5) for _ in range(10)]   # say nothing
s = socket.create_connection((host, 7777), timeout=5); s.sendall(b"GET / HTTP/1.0\r\n\r\n")  # wrong protocol
time.sleep(5)                             # past GATE_TIMEOUT_SECONDS
for h in half: h.close()
s.close()
# a well-formed connect request with a bogus version must reach the game (it answers with a kick)
s = socket.create_connection((host, 7777), timeout=5); s.sendall(b"\x0c\x00\x01\x0bTerraria000"); s.settimeout(5)
data = s.recv(64); s.close()
print("gate forwarded a real connect request; server replied", len(data), "bytes")
PY
sleep 3
[[ "$(docker inspect -f '{{.State.Running}}' "$name")" == true ]] || fail "server died under connection abuse"
docker logs "$name" 2>&1 | grep -c "FATAL UNHANDLED EXCEPTION" >/dev/null && fail "the server crashed anyway"
[[ "$(in_game 'game_players')" == 0 ]] || fail "server unresponsive after the abuse"
dropped=$(docker exec "$name" gameops http get http://127.0.0.1:9110/metrics | grep -E '^gameops_gate_dropped_total ' | cut -d' ' -f2)
passed=$(docker exec "$name" gameops http get http://127.0.0.1:9110/metrics | grep -E '^gameops_gate_passed_total ' | cut -d' ' -f2)
echo "    gate: dropped=${dropped} passed=${passed}"
(( dropped >= 51 && passed == 1 )) || fail "unexpected gate counters (dropped=${dropped}, passed=${passed})"

step "graceful stop on SIGTERM saves the world"
before=$(docker exec "$name" stat -c %Y /data/worlds/smoke.wld)
sleep 1
docker stop -t 150 "$name" >/dev/null
code=$(docker inspect -f '{{.State.ExitCode}}' "$name")
[[ "$code" == 0 ]] || fail "expected exit 0 after SIGTERM, got ${code}"
wait_for "STOP notification" 'Smoke server has shut down' 10
after=$(docker run --rm --volumes-from "$name" --entrypoint stat "$GAME_IMAGE" -c %Y /data/worlds/smoke.wld)
(( after > before )) || fail "smoke.wld was not saved on shutdown (mtime ${before} → ${after})"

echo "SMOKE OK"
