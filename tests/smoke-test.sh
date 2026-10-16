#!/usr/bin/env bash
# Build the add-on image and check that it actually comes up, without a
# Home Assistant Supervisor around it.
#
#   ./tests/smoke-test.sh            build + test
#   ./tests/smoke-test.sh --no-build test an already built codexpro:test image
#
# What it verifies:
#   * the image builds
#   * run.sh survives a start with no Supervisor (no crash loop)
#   * the web interface answers on 7680 and the terminal on 7681
#   * the persistent tmux session exists
#   * config.toml is generated and parses
#   * the helper commands are installed and runnable
#   * only the ingress address reaches the web interface, the terminal
#     listens on loopback, and DEV_DIRECT_ACCESS=1 opens both
#   * the files sidebar API stays inside /config and hides .git
#   * uploads get their extension from the MIME type
#   * the terminal WebSocket works through the /terminal proxy
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="codexpro:test"
NAME="codexpro-smoke"
DIRECT="codexpro-smoke-direct"
NET="codexpro-smoke-net"
# Same range as the Supervisor's hassio network, so the client can take the
# ingress proxy's address (172.30.32.2)
SUBNET="172.30.32.0/23"
INGRESS_IP="172.30.32.2"
ADDON_IP="172.30.33.10"
DIRECT_IP="172.30.33.11"
OTHER_IP="172.30.32.50"
WORK="$(mktemp -d)"
FAILED=0

cleanup() {
    docker rm -f "${NAME}" "${DIRECT}" >/dev/null 2>&1
    docker network rm "${NET}" >/dev/null 2>&1
    # Files created by the container are root-owned
    docker run --rm -v "${WORK}:/w" --entrypoint sh "${IMAGE}" -c 'rm -rf /w/*' >/dev/null 2>&1
    rm -rf "${WORK}"
}
trap cleanup EXIT

check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  [ ok ] %s\n' "${label}"
    else
        printf '  [FAIL] %s\n' "${label}"
        FAILED=$((FAILED + 1))
    fi
}

if [ "${1:-}" != "--no-build" ]; then
    echo "Building ${IMAGE}..."
    docker build \
        --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-python:3.13-alpine3.21 \
        --build-arg BUILD_ARCH=amd64 \
        -t "${IMAGE}" "${REPO_ROOT}/codexpro" || exit 1
fi

mkdir -p "${WORK}/data" "${WORK}/ha" "${WORK}/share" "${WORK}/media" "${WORK}/addon_configs"
cat > "${WORK}/data/options.json" <<'JSON'
{
  "auto_launch_codex": true,
  "model": "",
  "approval_policy": "on-request",
  "file_access": "workspace",
  "enable_ha_mcp": true,
  "openai_api_key": "",
  "auto_update_codex": false,
  "tmux_mouse": false,
  "persistent_apk_packages": [],
  "persistent_pip_packages": []
}
JSON

# Something for the files sidebar to show and to keep hidden
mkdir -p "${WORK}/ha/.git" "${WORK}/ha/packages"
echo "homeassistant:" > "${WORK}/ha/configuration.yaml"
echo "light: []" > "${WORK}/ha/packages/lights.yaml"
echo "[remote] url = https://token@example.com" > "${WORK}/ha/.git/config"
ln -s /etc/passwd "${WORK}/ha/escape"

echo "Starting containers..."
docker rm -f "${NAME}" "${DIRECT}" >/dev/null 2>&1
docker network rm "${NET}" >/dev/null 2>&1
docker network create --subnet "${SUBNET}" "${NET}" >/dev/null || exit 1
mkdir -p "${WORK}/direct-data"
cp "${WORK}/data/options.json" "${WORK}/direct-data/"
docker run -d --name "${DIRECT}" --network "${NET}" --ip "${DIRECT_IP}" \
    -e DEV_DIRECT_ACCESS=1 \
    -v "${WORK}/direct-data:/data" \
    "${IMAGE}" >/dev/null || exit 1
docker run -d --name "${NAME}" --network "${NET}" --ip "${ADDON_IP}" \
    -v "${WORK}/data:/data" \
    -v "${WORK}/ha:/homeassistant" \
    -v "${WORK}/share:/share" \
    -v "${WORK}/media:/media" \
    -v "${WORK}/addon_configs:/addon_configs" \
    "${IMAGE}" >/dev/null || exit 1

# Wait for the last thing to come up (the terminal), not the first one - the
# web interface answers a couple of seconds before ttyd binds its port.
for _ in $(seq 1 45); do
    if docker exec "${NAME}" curl -sf http://127.0.0.1:7680/health >/dev/null 2>&1 &&
       docker exec "${NAME}" curl -sf http://127.0.0.1:7681/ >/dev/null 2>&1 &&
       docker exec "${NAME}" tmux has-session -t codex >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

for _ in $(seq 1 30); do
    docker exec "${DIRECT}" curl -sf http://127.0.0.1:7681/ >/dev/null 2>&1 && break
    sleep 2
done

# curl from a separate container on the test network, from a chosen address
curl_from() {
    local ip="$1"; shift
    docker run --rm --network "${NET}" --ip "${ip}" --entrypoint curl "${IMAGE}" -sf -m 5 "$@"
}
api() {
    docker exec "${NAME}" curl -sf "http://127.0.0.1:7680$1"
}
api_status() {
    docker exec "${NAME}" curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:7680$1"
}

echo "Checking:"
check "container still running"          test "$(docker inspect -f '{{.State.Running}}' "${NAME}")" = "true"
check "web interface answers (7680)"     docker exec "${NAME}" curl -sf http://127.0.0.1:7680/health
check "terminal answers (7681)"          docker exec "${NAME}" curl -sf http://127.0.0.1:7681/
check "persistent tmux session exists"   docker exec "${NAME}" tmux has-session -t codex
check "/config points at /homeassistant" docker exec "${NAME}" sh -c "test -L /config"
check "codex runs"                       docker exec "${NAME}" codex --version
check "config.toml parses"               docker exec "${NAME}" python3 -c \
    "import tomllib;tomllib.load(open('/data/codex/config.toml','rb'))"
check "AGENTS.md written"                docker exec "${NAME}" sh -c "test -s /data/codex/AGENTS.md"
check "codex-update --check"             docker exec "${NAME}" codex-update --check
check "codex-doctor runs"                docker exec "${NAME}" bash -lc "codex-doctor >/dev/null"
check "persist-install --list"           docker exec "${NAME}" bash -lc "persist-install --list"
check "ha-reload --help"                 docker exec "${NAME}" ha-reload --help
check "hass-mcp installed"               docker exec "${NAME}" which hass-mcp
check "ha-api --help"                    docker exec "${NAME}" ha-api --help
check "ha-ws --help"                     docker exec "${NAME}" ha-ws --help
check "mcp-update --check"               docker exec "${NAME}" bash -lc "mcp-update --check"
check "AGENTS.md documents the API"      docker exec "${NAME}" sh -c "grep -q 'ha-api GET /api/states' /data/codex/AGENTS.md"
check "MCP has a start-up timeout"       docker exec "${NAME}" python3 -c \
    "import tomllib;c=tomllib.load(open('/data/codex/config.toml','rb'));assert c['mcp_servers']['homeassistant']['startup_timeout_sec'] >= 30"
check "no stray pytest shim shadowing test" docker exec "${NAME}" sh -c "! test -e /usr/local/bin/test"
check "ps understands the options Codex uses" docker exec "${NAME}" ps -o lstart= -p 1
docker exec "${NAME}" tmux new-session -d -s codexstart -x 150 -y 40 "codex; sleep 60"
sleep 8
check "codex actually starts (sign-in screen)" sh -c "docker exec ${NAME} tmux capture-pane -p -t codexstart | grep -q 'Sign in'"
docker exec "${NAME}" tmux kill-session -t codexstart >/dev/null 2>&1
check "node is new enough for the proxy"  docker exec "${NAME}" node -e \
    "const [a,b]=process.versions.node.split('.').map(Number);process.exit(a>22||(a===22&&b>=15)?0:1)"
# GHSA-vfj7-8cjw-p6xm (braces, no fixed version) is parsed from glob patterns
# only; http-proxy-middleware compiles one only for a glob pathFilter, and the
# proxy here has none, so no request ever reaches it.
AUDIT_ALLOWED="GHSA-vfj7-8cjw-p6xm"
check "web dependencies: no known vulnerabilities" sh -c "docker exec -w /opt/image-service ${NAME} npm audit --omit=dev --json |
    python3 -c \"import json,sys;a=json.load(sys.stdin)['vulnerabilities'];bad=[u for v in a.values() for x in v['via'] if isinstance(x,dict) for u in [x['url']] if not any(k in u for k in '${AUDIT_ALLOWED}'.split())];print(bad);sys.exit(1 if bad else 0)\""

echo "Access:"
check "ingress address reaches the web interface"   curl_from "${INGRESS_IP}" "http://${ADDON_IP}:7680/health"
check "other add-ons are refused (web interface)"   test "$(curl_from "${OTHER_IP}" -o /dev/null -w '%{http_code}' "http://${ADDON_IP}:7680/health")" = "000"
check "other add-ons are refused (terminal)"        test "$(curl_from "${OTHER_IP}" -o /dev/null -w '%{http_code}' "http://${ADDON_IP}:7681/")" = "000"
check "even ingress can't reach the bare terminal"  test "$(curl_from "${INGRESS_IP}" -o /dev/null -w '%{http_code}' "http://${ADDON_IP}:7681/")" = "000"
check "terminal listens on loopback only"           docker exec "${NAME}" sh -c "netstat -ltn | grep -q '127.0.0.1:7681'"
check "published ports: web interface open"         curl_from "${OTHER_IP}" "http://${DIRECT_IP}:7680/health"
check "published ports: terminal open"              curl_from "${OTHER_IP}" "http://${DIRECT_IP}:7681/"
check "page loads through ingress"                  sh -c "docker run --rm --network ${NET} --ip ${INGRESS_IP} --entrypoint curl ${IMAGE} -sf -m 5 http://${ADDON_IP}:7680/ | grep -q 'Codex Pro'"
check "terminal page through the proxy"             sh -c "docker run --rm --network ${NET} --ip ${INGRESS_IP} --entrypoint curl ${IMAGE} -sf -m 5 http://${ADDON_IP}:7680/terminal/ | grep -qi ttyd"
check "terminal WebSocket through the proxy"        docker exec "${NAME}" node -e '
const ws = new WebSocket("ws://127.0.0.1:7680/terminal/ws", ["tty"]);
const t = setTimeout(() => process.exit(1), 8000);
ws.onopen = () => ws.send(JSON.stringify({ AuthToken: "", columns: 80, rows: 24 }));
ws.onmessage = () => { clearTimeout(t); ws.close(); process.exit(0); };
ws.onerror = () => process.exit(1);'

echo "Files sidebar:"
check "roots list /homeassistant"          sh -c "docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/roots | grep -q '\"/homeassistant\"'"
check "folder listing works"               sh -c "docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/files?path=/config' | grep -q configuration.yaml"
check "folder listing hides .git"          sh -c "! docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/files?path=/config' | grep -q '\"name\":\".git\"'"
check "file preview works"                 sh -c "docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/file?path=/config/configuration.yaml' | grep -q homeassistant"
check "file outside /config refused"       test "$(api_status '/api/file?path=/etc/passwd')" = "404"
check "../ out of /config refused"         test "$(api_status '/api/file?path=/config/../etc/passwd')" = "404"
check "symlink out of /config refused"     test "$(api_status '/api/file?path=/config/escape')" = "404"
check ".git contents refused"              test "$(api_status '/api/file?path=/config/.git/config')" = "404"
check "recently changed files listed"      sh -c "docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/recent' | grep -q lights.yaml"
check "config check answers (no Supervisor)" sh -c "docker exec ${NAME} curl -sf -m 200 -X POST http://127.0.0.1:7680/api/ha/check | grep -q '\"ok\":false'"

echo "Image upload:"
docker exec "${NAME}" python3 -c "
import base64;open('/tmp/t.png','wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))"
check "extension comes from the MIME type" sh -c "docker exec ${NAME} curl -sf -F 'image=@/tmp/t.png;type=image/png;filename=photo.exe' http://127.0.0.1:7680/upload | grep -q 'pasted-[0-9]*\.png\"'"
check "jpeg upload gets .jpg"              sh -c "docker exec ${NAME} curl -sf -F 'image=@/tmp/t.png;type=image/jpeg;filename=noext' http://127.0.0.1:7680/upload | grep -q '\.jpg\"'"
check "non-images are rejected"            sh -c "! docker exec ${NAME} curl -sf -F 'image=@/etc/hostname;type=text/plain' http://127.0.0.1:7680/upload"
check "uploaded file is on disk"           docker exec "${NAME}" sh -c "ls /data/images/pasted-*.png"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "All checks passed."
else
    echo "${FAILED} check(s) failed. Container log:"
    docker logs "${NAME}" 2>&1 | tail -40
fi
exit "${FAILED}"
