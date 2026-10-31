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
#   * uploads take any file type, keep a cleaned-up name, never overwrite
#     each other and refuse files over 50 MB
#   * the Changes tab (git) tracks, diffs, reverts and checkpoints /config,
#     and never lists secrets
#   * startup removes only the old npm/pip caches; user files and notes are never deleted or left out of backups
#   * config.yaml leaves downloadable things out of backups
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

mkdir -p "${WORK}/data" "${WORK}/ha" "${WORK}/share" "${WORK}/media" "${WORK}/addon_configs" "${WORK}/addons"
# Leftovers of 1.2.x that startup must tidy: old caches, a stale upload and a
# fresh one (the fresh one must stay)
mkdir -p "${WORK}/data/.cache/npm/_cacache" "${WORK}/data/.cache/pip" "${WORK}/data/images" "${WORK}/data/.cache/other"
echo x > "${WORK}/data/.cache/npm/_cacache/blob"
echo x > "${WORK}/data/.cache/other/keep"
echo old > "${WORK}/data/images/pasted-1.png"
touch -d '40 days ago' "${WORK}/data/images/pasted-1.png"
echo new > "${WORK}/data/images/pasted-2.png"
# The user's own notes / saved conversations, wherever Codex may have put
# them, all older than any age limit: none may ever be deleted or left out
# of a backup
NOTES="home/zapisy/2026-09-01-porada.md codex/zapisy.md zapisy/topeni.md uploads/20260901-120000-poznamky.md images/poznamky.md .cache/poznamky.md .cache/other/notes.md home/.local/share/notes.md npm-notes/n.md"
for n in ${NOTES}; do mkdir -p "$(dirname "${WORK}/data/${n}")"; echo "# zapis ${n}" > "${WORK}/data/${n}"; touch -d '400 days ago' "${WORK}/data/${n}"; done
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
    -v "${WORK}/addons:/addons" \
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
check "MCP tools still ask by default"   docker exec "${NAME}" python3 -c \
    "import tomllib;c=tomllib.load(open('/data/codex/config.toml','rb'));assert 'default_tools_approval_mode' not in c['mcp_servers']['homeassistant']"
check "approval 'never' pre-approves MCP" docker exec "${NAME}" sh -c \
    "rm -rf /tmp/cx && mkdir /tmp/cx && codex-merge-config --config /tmp/cx/config.toml --approval-policy never --file-access workspace --enable-mcp true >/dev/null && grep -q 'default_tools_approval_mode = \"approve\"' /tmp/cx/config.toml"
check "Codex accepts that setting"       docker exec "${NAME}" sh -c \
    "CODEX_HOME=/tmp/cx codex mcp get homeassistant >/dev/null"
check "AGENTS.md says to fall back to the API" docker exec "${NAME}" sh -c "grep -q 'If an MCP tool fails with an error' /data/codex/AGENTS.md"
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

echo "File upload:"
docker exec "${NAME}" python3 -c "
import base64;open('/tmp/t.png','wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))"
docker exec "${NAME}" sh -c "printf 'automation: []\n' > /tmp/a.yaml; head -c 1048576 /dev/urandom > /tmp/big.bin; head -c 52428801 /dev/zero > /tmp/toobig.bin"
up() { docker exec "${NAME}" curl -s -m 60 -F "file=@$1" http://127.0.0.1:7680/upload; }
check "image keeps its name and extension"  sh -c "docker exec ${NAME} curl -sf -F 'file=@/tmp/t.png;type=image/png;filename=My Shot (1).png' http://127.0.0.1:7680/upload | grep -q '/data/uploads/[0-9]\{8\}-[0-9]\{6\}-My-Shot-1\.png\"'"
check "clipboard image without a name"      sh -c "docker exec ${NAME} curl -sf -F 'file=@/tmp/t.png;type=image/jpeg;filename=noext' http://127.0.0.1:7680/upload | grep -q 'noext\.jpg\"'"
check "YAML is accepted"                    sh -c "docker exec ${NAME} curl -sf -F 'file=@/tmp/a.yaml;type=application/x-yaml;filename=automations.yaml' http://127.0.0.1:7680/upload | grep -q 'automations\.yaml\"'"
check "PDF/any type is accepted"            sh -c "docker exec ${NAME} curl -sf -F 'file=@/tmp/big.bin;type=application/pdf;filename=report.PDF' http://127.0.0.1:7680/upload | grep -q 'report\.pdf\"'"
check "1 MB file arrives intact"            sh -c "test \"\$(docker exec ${NAME} sh -c 'md5sum < /tmp/big.bin')\" = \"\$(docker exec ${NAME} sh -c 'md5sum /data/uploads/*-report.pdf | cut -c1-32')  -\""
check "path characters are stripped"        sh -c "docker exec ${NAME} curl -sf -F 'file=@/tmp/a.yaml;filename=\"../../etc/x;y\$(id).sh\"' http://127.0.0.1:7680/upload | grep -q '\"/data/uploads/[0-9-]*x-y-id\.sh\"'"
check "nothing written outside uploads"     docker exec "${NAME}" sh -c "! ls /etc/x* /data/x* 2>/dev/null | grep -q ."
check "over 50 MB is refused with advice"   sh -c "docker exec ${NAME} curl -s -m 60 -F 'file=@/tmp/toobig.bin;filename=huge.bin' http://127.0.0.1:7680/upload | grep -q 'larger than 50 MB - put it in /share'"
check "refused file leaves nothing behind"  docker exec "${NAME}" sh -c "! ls /data/uploads/*huge* 2>/dev/null | grep -q ."
check "missing file gets an answer"         sh -c "docker exec ${NAME} curl -s -X POST http://127.0.0.1:7680/upload | grep -q 'No file arrived'"
check "20 same-name uploads at once: 20 files" sh -c "docker exec ${NAME} sh -c 'for i in \$(seq 1 20); do curl -s -F \"file=@/tmp/a.yaml;filename=same.yaml\" http://127.0.0.1:7680/upload >/dev/null & done; wait; ls /data/uploads/*same*.yaml | wc -l' | grep -qx 20"
check "  ... and none of them is empty"     docker exec "${NAME}" sh -c "! find /data/uploads -name '*same*' -empty | grep -q ."

echo "Tidying /data:"
check "old npm cache removed"               docker exec "${NAME}" sh -c "! test -e /data/.cache/npm"
check "old pip cache removed"               docker exec "${NAME}" sh -c "! test -e /data/.cache/pip"
check "other cache contents kept"           docker exec "${NAME}" test -f /data/.cache/other/keep
check "old uploads are never deleted"       docker exec "${NAME}" test -f /data/images/pasted-1.png
check "recent upload kept"                  docker exec "${NAME}" test -f /data/images/pasted-2.png
for n in ${NOTES}; do
check "user's note kept: /data/${n}"        docker exec "${NAME}" sh -c "grep -q 'zapis ${n}' '/data/${n}'"
done
check "npm cache now outside /data"         docker exec "${NAME}" bash -lc 'test "$NPM_CONFIG_CACHE" = /tmp/npm-cache && test "$PIP_NO_CACHE_DIR" = 1'
check "backup_exclude leaves out only downloaded programs" sh -c "python3 - <<'EOF'
import yaml,sys
c=yaml.safe_load(open('${REPO_ROOT}/codexpro/config.yaml'))
from pathlib import PurePath
ex=c['backup_exclude']
def out(p): return any(PurePath(p).match(e) for e in ex)
assert out('/data/addons/data/5c53de3b_codexpro/npm')
assert out('/data/addons/data/local_codexpro/.cache/npm')
assert out('/data/addons/data/local_codexpro/.cache/pip')
for keep in ['codex','codex/auth.json','home','packages','.ha-token','options.json','codex/sessions','uploads','images','.cache','.cache/other','zapisy','npm-notes']:
    assert not out('/data/addons/data/5c53de3b_codexpro/'+keep), keep
EOF"
# Walk the real /data the way Supervisor does (a file is left out when it or
# any folder above it matches backup_exclude): every .md, every conversation
# and the sign-in must go into the backup
docker exec "${NAME}" sh -c 'cd /data && find . \( -name "*.md" -o -name "*.jsonl" -o -name auth.json \) -print' > "${WORK}/datafiles.txt"
check "every note, conversation and sign-in in /data is backed up" sh -c "python3 - '${WORK}/datafiles.txt' <<'EOF'
import yaml,sys
from pathlib import PurePath
ex=yaml.safe_load(open('${REPO_ROOT}/codexpro/config.yaml'))['backup_exclude']
base=PurePath('/data/addons/data/5c53de3b_codexpro')
files=[l.strip()[2:] for l in open(sys.argv[1]) if l.strip()]
assert len(files) >= 9, files
lost=[]
for f in files:
    p=base/f
    if any(q.match(e) for q in [p,*p.parents] if q!=PurePath('/') for e in ex): lost.append(f)
assert not lost, lost
print(len(files),'files checked', file=sys.stderr)
EOF"
check "/addons is mapped and writable for Codex" sh -c "docker exec ${NAME} grep -q '\"/addons\"' /data/codex/config.toml && grep -q 'type: addons' '${REPO_ROOT}/codexpro/config.yaml'"
check "AGENTS.md explains /data/uploads"    docker exec "${NAME}" grep -q '/data/uploads' /data/codex/AGENTS.md
check "Codex is 0.166 or newer"             docker exec "${NAME}" sh -c "codex --version | awk '{split(\$2,v,\".\"); exit !(v[1]>0 || v[2]>=166)}'"
check "hass-mcp is 0.6.1 or newer"          docker exec "${NAME}" python3 -c "
from importlib.metadata import version; v=tuple(map(int,version('hass-mcp').split('.')[:3])); assert v>=(0,6,1), v"

echo "Changes tab (git):"
# The fake .git from the sidebar checks is not a repository; start clean
docker exec "${NAME}" sh -c "rm -rf /homeassistant/.git; printf 'api_key: hunter2\n' > /homeassistant/secrets.yaml; mkdir -p /homeassistant/.storage; echo '{}' > /homeassistant/.storage/core.config"
post() { docker exec "${NAME}" curl -s -X POST "http://127.0.0.1:7680$1"; }
check "untracked /config says so"           sh -c "docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q '\"repo\":false'"
check "start tracking"                      sh -c "docker exec ${NAME} curl -s -X POST http://127.0.0.1:7680/api/git/init | grep -q '\"ok\":true'"
check "starting twice is refused"           sh -c "docker exec ${NAME} curl -s -X POST http://127.0.0.1:7680/api/git/init | grep -q 'already being tracked'"
check ".gitignore written"                  docker exec "${NAME}" grep -qx 'secrets.yaml' /homeassistant/.gitignore
check "secrets.yaml never committed"        docker exec "${NAME}" sh -c "! git -C /homeassistant ls-files | grep -q -e secrets -e .storage"
check "no changes right after start"        sh -c "docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q '\"files\":\[\]'"
docker exec "${NAME}" sh -c "echo 'logger:' >> /homeassistant/configuration.yaml; echo 'new: 1' > /homeassistant/packages/new.yaml; echo 'api_key: changed' > /homeassistant/secrets.yaml"
check "changed file listed"                 sh -c "docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q '\"path\":\"configuration.yaml\",\"status\":\"modified\"'"
check "new file listed"                     sh -c "docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q 'packages/new.yaml'"
check "secrets.yaml never listed"           sh -c "! docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q secrets"
check "diff shows the added line"           sh -c "docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/git/diff?path=configuration.yaml' | grep -q '+logger:'"
check "diff of a new file works"            sh -c "docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/git/diff?path=packages/new.yaml' | grep -q '+new: 1'"
check "diff of secrets.yaml refused"        test "$(api_status '/api/git/diff?path=secrets.yaml')" = "400"
check "diff outside /config refused"        test "$(api_status '/api/git/diff?path=../etc/passwd')" = "400"
check "remotes reported (none)"             sh -c "docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q '\"remotes\":\[\]'"
check "new file cannot be 'reverted'"       sh -c "docker exec ${NAME} curl -s -X POST 'http://127.0.0.1:7680/api/git/revert?path=packages/new.yaml' | grep -q 'no earlier version'"
check "  ... and is still there"            docker exec "${NAME}" test -f /homeassistant/packages/new.yaml
check "revert restores the file"            sh -c "docker exec ${NAME} curl -s -X POST 'http://127.0.0.1:7680/api/git/revert?path=configuration.yaml' | grep -q '\"ok\":true' && ! docker exec ${NAME} grep -q logger /homeassistant/configuration.yaml"
check "revert of secrets.yaml refused"      sh -c "docker exec ${NAME} curl -s -X POST 'http://127.0.0.1:7680/api/git/revert?path=secrets.yaml' | grep -q 'is not tracked' && docker exec ${NAME} grep -q changed /homeassistant/secrets.yaml"
check "checkpoint accepts the changes"      sh -c "docker exec ${NAME} curl -s -X POST http://127.0.0.1:7680/api/git/checkpoint | grep -q '\"ok\":true'"
check "  ... secrets still not committed"   docker exec "${NAME}" sh -c "! git -C /homeassistant -c safe.directory='*' log --all --name-only --format= | grep -q -e secrets -e .storage"
check "  ... nothing left to accept"        sh -c "docker exec ${NAME} curl -s -X POST http://127.0.0.1:7680/api/git/checkpoint | grep -q 'Nothing to accept'"
docker exec "${NAME}" git -C /homeassistant -c safe.directory='*' remote add origin https://user:tok@example.com/r.git
check "remote name reported, URL is not"    sh -c "docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q '\"remotes\":\[\"origin\"\]' && ! docker exec ${NAME} curl -sf http://127.0.0.1:7680/api/git/status | grep -q example.com"
check "folder listing still hides .git"     sh -c "! docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/files?path=/config' | grep -q '\"name\":\".git\"'"
check "recent list skips .git"              sh -c "! docker exec ${NAME} curl -sf 'http://127.0.0.1:7680/api/recent' | grep -q '/.git/'"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "All checks passed."
else
    echo "${FAILED} check(s) failed. Container log:"
    docker logs "${NAME}" 2>&1 | tail -40
fi
exit "${FAILED}"
