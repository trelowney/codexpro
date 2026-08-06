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
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="codexpro:test"
NAME="codexpro-smoke"
WORK="$(mktemp -d)"
FAILED=0

cleanup() {
    docker rm -f "${NAME}" >/dev/null 2>&1
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

echo "Starting container..."
docker rm -f "${NAME}" >/dev/null 2>&1
docker run -d --name "${NAME}" \
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
check "no stray pytest shim shadowing test" docker exec "${NAME}" sh -c "! test -e /usr/local/bin/test"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "All checks passed."
else
    echo "${FAILED} check(s) failed. Container log:"
    docker logs "${NAME}" 2>&1 | tail -40
fi
exit "${FAILED}"
