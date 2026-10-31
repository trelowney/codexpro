#!/usr/bin/with-contenv bashio
# ---------------------------------------------------------------------------
# Codex Pro for Home Assistant - add-on entrypoint
#
# Design goals (the three things this fork exists to fix):
#   1. The Codex session must survive a browser reload and a Home Assistant
#      Core restart -> a detached tmux session is created here, ttyd only
#      attaches to it.
#   2. Updating the Codex CLI from inside the container must never hit
#      "permission denied" -> everything runs as root and the writable npm
#      prefix lives on the persistent /data volume.
#   3. Codex must be able to edit Home Assistant files (dashboards, YAML,
#      other add-on configs) -> the mapped folders are writable roots of the
#      Codex sandbox and /config points at the HA config folder.
# ---------------------------------------------------------------------------

set -e
set -o pipefail

# Read an add-on option and never come back empty-handed. bashio returns "null"
# for an unset option and can fail outright while the Supervisor API is busy,
# and a half-read option must not be able to break the start-up.
config_value() {
    local key="$1" fallback="${2:-}" value
    value="$(bashio::config "${key}" 2>/dev/null || true)"
    case "${value}" in
        ""|null|"[]") value="${fallback}" ;;
    esac
    printf '%s' "${value}"
}

# Same, but the answer has to be one of a fixed set of words.
config_choice() {
    local key="$1" fallback="$2"; shift 2
    local value allowed
    value="$(config_value "${key}" "${fallback}")"
    for allowed in "$@"; do
        [ "${value}" = "${allowed}" ] && { printf '%s' "${value}"; return; }
    done
    bashio::log.warning "Option '${key}' has an unusable value ('${value}'); using '${fallback}' instead."
    bashio::log.warning "Fix it in the add-on Configuration tab if that is not what you want."
    printf '%s' "${fallback}"
}

config_bool() {
    local value
    value="$(config_value "$1" "$2")"
    case "${value}" in
        true|True|yes|on|1) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

DATA_ROOT="/data"
CODEX_STATE="${DATA_ROOT}/codex"          # CODEX_HOME: auth.json, sessions, history
DATA_HOME="${DATA_ROOT}/home"             # HOME
NPM_ROOT="${DATA_ROOT}/npm"               # persistent global npm prefix
PERSIST_ROOT="${DATA_ROOT}/packages"      # persist-install target
TTYD_PORT=7681
WEB_PORT=7680
TMUX_SESSION="codex"

# ---------------------------------------------------------------------------
# Environment: everything that must survive a restart lives in /data
# ---------------------------------------------------------------------------
init_environment() {
    bashio::log.info "Preparing persistent environment in ${DATA_ROOT}..."

    mkdir -p \
        "${CODEX_STATE}" \
        "${DATA_HOME}/.local/bin" \
        "${DATA_ROOT}/.config/gh" \
        "${DATA_ROOT}/.cache" \
        "${DATA_ROOT}/.local/state" \
        "${DATA_ROOT}/.local/share" \
        "${DATA_ROOT}/uploads" \
        "${NPM_ROOT}/bin" \
        "${PERSIST_ROOT}/bin" \
        "${PERSIST_ROOT}/lib" \
        "${PERSIST_ROOT}/python"

    chmod 700 "${CODEX_STATE}"

    export HOME="${DATA_HOME}"
    export CODEX_HOME="${CODEX_STATE}"
    export XDG_CONFIG_HOME="${DATA_ROOT}/.config"
    export XDG_CACHE_HOME="${DATA_ROOT}/.cache"
    export XDG_STATE_HOME="${DATA_ROOT}/.local/state"
    export XDG_DATA_HOME="${DATA_ROOT}/.local/share"
    export GH_CONFIG_DIR="${DATA_ROOT}/.config/gh"
    export NPM_CONFIG_PREFIX="${NPM_ROOT}"
    export NPM_CONFIG_CACHE="/tmp/npm-cache"
    export PIP_NO_CACHE_DIR=1
    export PATH="${NPM_ROOT}/bin:${PERSIST_ROOT}/bin:${PERSIST_ROOT}/python/venv/bin:${DATA_HOME}/.local/bin:${PATH}"
    export LD_LIBRARY_PATH="${PERSIST_ROOT}/lib:${LD_LIBRARY_PATH:-}"
    export PKG_CONFIG_PATH="${PERSIST_ROOT}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    # Codex refuses to run as root unless it is told it is inside a sandboxed
    # container. In an HA add-on the container *is* the sandbox.
    export IS_SANDBOX=1
    export CODEX_UPLOAD_DIR="${DATA_ROOT}/uploads"

    if [ -d "${PERSIST_ROOT}/python/venv" ]; then
        export VIRTUAL_ENV="${PERSIST_ROOT}/python/venv"
    fi

    # The same environment for every shell ttyd/tmux spawns later on.
    cat > /etc/profile.d/codexpro.sh << PROFILE_EOF
# Managed by the Codex Pro add-on - do not edit, it is rewritten on every start.
export HOME="${DATA_HOME}"
export CODEX_HOME="${CODEX_STATE}"
export XDG_CONFIG_HOME="${DATA_ROOT}/.config"
export XDG_CACHE_HOME="${DATA_ROOT}/.cache"
export XDG_STATE_HOME="${DATA_ROOT}/.local/state"
export XDG_DATA_HOME="${DATA_ROOT}/.local/share"
export GH_CONFIG_DIR="${DATA_ROOT}/.config/gh"
export NPM_CONFIG_PREFIX="${NPM_ROOT}"
export NPM_CONFIG_CACHE="/tmp/npm-cache"
export PIP_NO_CACHE_DIR=1
export PATH="${NPM_ROOT}/bin:${PERSIST_ROOT}/bin:${PERSIST_ROOT}/python/venv/bin:${DATA_HOME}/.local/bin:\${PATH}"
export LD_LIBRARY_PATH="${PERSIST_ROOT}/lib:\${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="${PERSIST_ROOT}/lib/pkgconfig:\${PKG_CONFIG_PATH:-}"
export IS_SANDBOX=1
export CODEX_UPLOAD_DIR="${DATA_ROOT}/uploads"
export TERM=xterm-256color
[ -d "${PERSIST_ROOT}/python/venv" ] && export VIRTUAL_ENV="${PERSIST_ROOT}/python/venv"

alias ll='ls -la'
alias ha-config='cd /homeassistant'
PS1='\[\033[1;36m\]codex\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '
PROFILE_EOF
    chmod 644 /etc/profile.d/codexpro.sh

    cat > "${DATA_HOME}/.bashrc" << 'BASHRC_EOF'
[ -f /etc/profile.d/codexpro.sh ] && . /etc/profile.d/codexpro.sh
BASHRC_EOF
    cp "${DATA_HOME}/.bashrc" "${DATA_HOME}/.profile"

    bashio::log.info "  HOME=${HOME}  CODEX_HOME=${CODEX_HOME}"
}

# ---------------------------------------------------------------------------
# Keep /data small: it goes into every Home Assistant backup
# ---------------------------------------------------------------------------
# Before 1.3.0 the npm and pip caches lived in /data/.cache and grew with every
# Codex update. They now live in /tmp (gone on restart), so delete the old ones.
# NOTHING ELSE is ever deleted here: people keep notes and saved conversations
# in /data (and uploads may be the only copy of something), so user files are
# never pruned, whatever their age or folder.
tidy_data() {
    rm -rf "${DATA_ROOT}/.cache/npm" "${DATA_ROOT}/.cache/pip" 2>/dev/null || true
    return 0
}

# ---------------------------------------------------------------------------
# /config -> /homeassistant, so both path habits work
# ---------------------------------------------------------------------------
setup_config_alias() {
    # Report what the Supervisor actually mounted. Mount points have moved
    # between Supervisor generations, so this is checked instead of assumed -
    # and it is the first thing to look at when Codex says a file is missing.
    local folder found=""
    for folder in /homeassistant /addon_configs /share /media /addons /ssl /backup; do
        [ -d "${folder}" ] && found="${found} ${folder}"
    done
    bashio::log.info "Mapped folders:${found:- none}"

    if [ ! -d /homeassistant ]; then
        bashio::log.error "The Home Assistant configuration folder is not mounted."
        bashio::log.error "Codex will start but cannot see your configuration."
        bashio::log.error "What to do: uninstall and reinstall the add-on; if it persists,"
        bashio::log.error "report it with the 'Mapped folders' line above."
    fi

    if [ ! -e /config ] && [ -d /homeassistant ]; then
        ln -s /homeassistant /config
        bashio::log.info "Path alias created: /config -> /homeassistant"
    elif [ -L /config ]; then
        bashio::log.info "Path alias present: /config -> $(readlink /config)"
    elif [ -d /config ]; then
        bashio::log.info "/config already exists as a real folder, leaving it alone"
    fi
}

# ---------------------------------------------------------------------------
# Codex CLI: persistent, updatable install in /data/npm
# ---------------------------------------------------------------------------
setup_codex_cli() {
    local auto_update
    auto_update="$(config_bool 'auto_update_codex' 'false')"

    if [ "${auto_update}" = "true" ]; then
        bashio::log.info "auto_update_codex is on - updating @openai/codex in ${NPM_ROOT}..."
        if npm install -g @openai/codex@latest --prefer-online >/tmp/codex-update.log 2>&1; then
            bashio::log.info "Codex CLI updated"
            rm -rf /tmp/npm-cache 2>/dev/null || true
        else
            bashio::log.warning "Codex CLI update failed - keeping the version baked into the image."
            bashio::log.warning "You can retry later from the terminal with:  codex-update"
            tail -n 10 /tmp/codex-update.log 2>/dev/null | while IFS= read -r l; do
                bashio::log.warning "  ${l}"
            done
        fi
    fi

    # A persistent install always wins over the image one, but only if it
    # actually runs (a stale or wrong-arch copy in /data must not brick the add-on).
    if [ -x "${NPM_ROOT}/bin/codex" ] && ! timeout 20 "${NPM_ROOT}/bin/codex" --version >/dev/null 2>&1; then
        bashio::log.warning "The Codex copy in ${NPM_ROOT} does not run - ignoring it and using the built-in one."
        bashio::log.warning "To repair it, run in the terminal:  codex-update --reset"
        mv "${NPM_ROOT}/bin/codex" "${NPM_ROOT}/bin/codex.broken" 2>/dev/null || true
    fi

    bashio::log.info "Codex CLI in use: $(command -v codex) ($(codex --version 2>/dev/null || echo 'version unknown'))"
}

# ---------------------------------------------------------------------------
# Supervisor token + Home Assistant MCP server
# ---------------------------------------------------------------------------
setup_ha_access() {
    local token_file="${DATA_ROOT}/.ha-token"

    printf '%s' "${SUPERVISOR_TOKEN:-}" > "${token_file}"
    chmod 600 "${token_file}"

    # ha CLI, the API helpers and the MCP wrapper all read this.
    {
        echo "export SUPERVISOR_TOKEN=\"\$(cat ${token_file})\""
        echo "export HASSIO_TOKEN=\"\$(cat ${token_file})\""
        echo "export HA_URL=\"http://supervisor/core\""
        echo "export HA_TOKEN=\"\$(cat ${token_file})\""
    } >> /etc/profile.d/codexpro.sh
}

# ---------------------------------------------------------------------------
# Home Assistant MCP server: updatable, like the CLI itself
# ---------------------------------------------------------------------------
setup_ha_mcp_server() {
    local auto_update persistent_mcp="/data/packages/python/venv/bin/hass-mcp"

    auto_update="$(config_bool 'auto_update_ha_mcp' 'false')"

    if [ "${auto_update}" = "true" ]; then
        bashio::log.info "auto_update_ha_mcp is on - updating hass-mcp in /data..."
        if mcp-update >/tmp/mcp-update.log 2>&1; then
            bashio::log.info "Home Assistant MCP server updated"
        else
            bashio::log.warning "MCP server update failed - keeping the version baked into the image."
            bashio::log.warning "You can retry later from the terminal with:  mcp-update"
            tail -n 5 /tmp/mcp-update.log 2>/dev/null | while IFS= read -r l; do
                bashio::log.warning "  ${l}"
            done
        fi
    fi

    # As with the CLI: a persistent copy only wins if it actually runs.
    if [ -x "${persistent_mcp}" ] && ! timeout 20 "${persistent_mcp}" --help >/dev/null 2>&1; then
        bashio::log.warning "The hass-mcp copy in /data does not run - using the built-in one instead."
        bashio::log.warning "To repair it, run in the terminal:  mcp-update --reset"
        mv "${persistent_mcp}" "${persistent_mcp}.broken" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Warm the MCP server up before Codex ever asks for it
# ---------------------------------------------------------------------------
# Codex is launched a couple of seconds from here and waits only briefly for
# its MCP servers, so start hass-mcp once in the background and throw the
# result away. This buys nothing on a fast disk - measured 1.57 s warm against
# 1.52-1.69 s cold, the handshake is spent importing Python and the MCP SDK,
# not reading them - and is kept for the case it was written for: a small board
# on slow flash, where that first read is the expensive part. The real
# protection is 'startup_timeout_sec' in config.toml.
# Failures here are deliberately silent: this is an optimisation, and
# 'setup_ha_mcp_server' has already reported anything that actually matters.
warm_up_ha_mcp() {
    [ "$(config_bool 'enable_ha_mcp' 'true')" = "true" ] || return 0
    ( timeout 30 hass-mcp-wrapper </dev/null >/dev/null 2>&1 || true ) &
}

# ---------------------------------------------------------------------------
# Can Codex run commands in its own sandbox here?
# ---------------------------------------------------------------------------
# file_access: workspace makes Codex run every command inside bubblewrap. Home
# Assistant's add-on container does not allow that ("bwrap: Failed to make /
# slave: Permission denied"), and then Codex cannot run a single command -
# not ha-api, not even ls. Try one harmless command the way Codex does; if it
# fails, fall back to full access (the add-on container itself is the
# isolation and only sees the mapped folders) and say so.
SANDBOX_STATUS_FILE="/run/codexpro-sandbox"

workspace_sandbox_works() {
    local out
    out="$(cd /homeassistant 2>/dev/null || cd /; timeout 30 codex sandbox \
        -c 'sandbox_mode="workspace-write"' -- sh -c 'echo codexpro-sandbox-ok' 2>&1)"
    case "${out}" in
        *codexpro-sandbox-ok*) return 0 ;;
    esac
    printf '%s\n' "${out}" | grep -v 'arg0 temp' | grep -v '^\s*$' | head -n 3 > "${SANDBOX_STATUS_FILE}.error"
    return 1
}

# ---------------------------------------------------------------------------
# Codex configuration (~/.codex/config.toml) - merged, never overwritten
# ---------------------------------------------------------------------------
setup_codex_config() {
    local model approval file_access enable_mcp api_key
    model="$(config_value 'model' '')"
    approval="$(config_choice 'approval_policy' 'on-request' untrusted on-failure on-request never)"
    file_access="$(config_choice 'file_access' 'full' workspace full)"
    enable_mcp="$(config_bool 'enable_ha_mcp' 'true')"
    api_key="$(config_value 'openai_api_key' '')"

    rm -f "${SANDBOX_STATUS_FILE}" "${SANDBOX_STATUS_FILE}.error"
    if [ "${file_access}" = "workspace" ]; then
        if workspace_sandbox_works; then
            echo "workspace" > "${SANDBOX_STATUS_FILE}"
            bashio::log.info "File access: workspace (Codex's sandbox works here)"
        else
            echo "fallback" > "${SANDBOX_STATUS_FILE}"
            bashio::log.warning "File access 'workspace' cannot work in this container: Codex could not run any command in its sandbox:"
            while IFS= read -r line; do bashio::log.warning "  ${line}"; done < "${SANDBOX_STATUS_FILE}.error"
            bashio::log.warning "Using full access instead, so Codex can run commands (ha-api, ls, ...). To stop this message, set 'file_access: full' in the add-on configuration."
            file_access="full"
        fi
    else
        echo "full" > "${SANDBOX_STATUS_FILE}"
        bashio::log.info "File access: full"
    fi

    install_agents_md

    if ! codex-merge-config \
            --config "${CODEX_STATE}/config.toml" \
            --model "${model}" \
            --approval-policy "${approval}" \
            --file-access "${file_access}" \
            --enable-mcp "${enable_mcp}"; then
        bashio::log.error "Could not write ${CODEX_STATE}/config.toml."
        bashio::log.error "The terminal still starts; run 'codex-doctor' inside it to see what is wrong."
    fi

    if [ -n "${api_key}" ]; then
        export OPENAI_API_KEY="${api_key}"
        echo "export OPENAI_API_KEY=\"${api_key}\"" >> /etc/profile.d/codexpro.sh
        bashio::log.info "OPENAI_API_KEY taken from the add-on configuration"
    fi

    if [ "${enable_mcp}" = "true" ]; then
        bashio::log.info "Home Assistant MCP server: enabled"
    else
        bashio::log.info "Home Assistant MCP server: disabled"
    fi
}

install_agents_md() {
    cat > "${CODEX_STATE}/AGENTS.md" << 'AGENTS_EOF'
# Codex Pro - Home Assistant add-on

This file is generated by the add-on on every start. Do not edit it; put your
own instructions in `/config/AGENTS.md` (equivalently `/homeassistant/AGENTS.md`).

## Paths inside this container

| Path | What it is | Access |
|------|------------|--------|
| `/homeassistant` | Home Assistant configuration folder | read-write |
| `/config` | symlink to `/homeassistant` (same folder) | read-write |
| `/addon_configs` | configuration folders of other add-ons | read-write |
| `/share` | shared folder | read-write |
| `/media` | media folder | read-write |
| `/addons` | local add-ons (for writing your own add-on) | read-write |
| `/ssl` | certificates | read-only |
| `/backup` | backups | read-only |
| `/data` | this add-on's own persistent state | read-write |
| `/data/uploads` | files the user uploaded in the panel (📎, paste, drag-and-drop) | read-write |

When the user gives you a path in `/data/uploads`, read that file; it can be
an image, a PDF, YAML, a log or anything else. Uploads are kept and backed
up; never delete files in `/data` you did not create yourself for a task.

In HA Core documentation the config folder is called `/config`; here both
`/config` and `/homeassistant` point at the same place, so either works.

## Dashboards

- YAML dashboards live in `/config` and take effect after a config reload.
- UI dashboards live in `/config/.storage/lovelace*`. They are JSON, they are
  cached in memory by Home Assistant, and a change only shows up after a
  restart. Always back the file up before editing it, and tell the user that a
  Home Assistant restart is needed.
- After editing YAML, validate with `ha core check`, then apply with
  `ha-reload` (a helper command in this container).

## Useful commands

```bash
ha core check              # validate the configuration
ha core restart            # restart Home Assistant Core
ha core logs | tail -100   # recent logs
ha-reload                  # reload config without a full restart
```

## Three ways to reach Home Assistant

You have all three. Use whichever fits; they are not alternatives to each other.

1. **The files** in `/config` - for YAML you can read and edit directly.
2. **The `homeassistant` MCP server** (when enabled) - declared tools for
   entities, services, history, statistics and UI dashboards. Prefer these when
   one of them covers the task, they are the least error-prone.
3. **The API helpers below** - everything the MCP tools do not cover. They are
   already authenticated; there is no token to look up and no host name to
   guess.

If an MCP tool fails with an error, do the same thing with `ha-api` or `ha-ws`
instead of stopping - reading a dashboard, for example, is `ha-ws
lovelace/config`. If the user declined a tool call, respect that and do not
redo it through the API.

### `ha-api` - the REST API

```bash
ha-api GET /api/states                       # every entity and its state
ha-api GET /api/states/light.kitchen         # one entity
ha-api GET /api/config                       # version, location, units
ha-api GET /api/services                     # every callable service
ha-api GET /api/error_log                    # the error log
ha-api POST /api/services/light/turn_on '{"entity_id":"light.kitchen"}'
ha-api POST /api/template '{"template":"{{ states(\"sun.sun\") }}"}'
ha-api --supervisor GET /addons/self/info    # the Supervisor API
```

### `ha-ws` - the WebSocket API

For what REST cannot do at all - UI dashboards and the registries:

```bash
ha-ws lovelace/config '{"url_path": null}'   # read the default dashboard
ha-ws lovelace/dashboards/list               # list UI dashboards
ha-ws config/area_registry/list
ha-ws config/device_registry/list
ha-ws config/entity_registry/list
ha-ws lovelace/config/save '{"url_path": null, "config": { ... }}'
```

`lovelace/config/save` **replaces the whole dashboard**, it does not merge.
Read the current config, change that object, send all of it back - and save a
copy of the original first. Editing a dashboard through the API takes effect
immediately; editing `/config/.storage/lovelace*` by hand does not, because
Home Assistant keeps it in memory.

Run any of these with `--help` for more. Both print what went wrong and what to
do about it rather than a bare error.
AGENTS_EOF
}

# ---------------------------------------------------------------------------
# tmux: the reason a session survives disconnects
# ---------------------------------------------------------------------------
setup_tmux() {
    local mouse
    mouse="$(config_bool 'tmux_mouse' 'false')"
    case "${mouse}" in
        true|on|yes|1) mouse="on" ;;
        *) mouse="off" ;;
    esac

    cat > "${DATA_HOME}/.tmux.conf" << TMUX_EOF
set -g mouse ${mouse}
set -g history-limit 50000
set -g escape-time 20
set -g base-index 1
set -g renumber-windows on
set -ga terminal-overrides ',xterm*:smcup@:rmcup@'
set -g allow-passthrough on
# Let programs in the pane set the browser clipboard through OSC 52, and pass
# it on to the terminal page. tmux only does that when the outer terminal
# declares clipboard support, which ttyd's page always has.
set -g set-clipboard on
set -as terminal-features ',*:clipboard'
set -g status-bg colour235
set -g status-fg colour136
set -g status-left '[codex] '
set -g status-right 'Codex Pro | %H:%M'
TMUX_EOF
}

# ---------------------------------------------------------------------------
# Persistent extra packages
# ---------------------------------------------------------------------------
setup_persistent_packages() {
    local apk_packages pip_packages package
    local -a pip_list=()

    apk_packages="$(normalize_config_list "$(config_value 'persistent_apk_packages' '')")"
    pip_packages="$(normalize_config_list "$(config_value 'persistent_pip_packages' '')")"

    if [ -n "${apk_packages}" ]; then
        bashio::log.info "Installing persistent system packages from the configuration..."
        while IFS= read -r package; do
            [ -z "${package}" ] && continue
            bashio::log.info "  ${package}"
            persist-install "${package}" >/dev/null 2>&1 || \
                bashio::log.warning "  could not install '${package}' - check the package name in the add-on configuration"
        done <<< "${apk_packages}"
    fi

    if [ -n "${pip_packages}" ]; then
        while IFS= read -r package; do
            [ -n "${package}" ] && pip_list+=("${package}")
        done <<< "${pip_packages}"
        if [ "${#pip_list[@]}" -gt 0 ]; then
            bashio::log.info "Installing persistent Python packages: ${pip_list[*]}"
            persist-install --python "${pip_list[@]}" >/dev/null 2>&1 || \
                bashio::log.warning "  could not install the Python packages - check their names in the add-on configuration"
        fi
    fi
}

normalize_config_list() {
    local raw="$1"
    if [ -z "${raw}" ] || [ "${raw}" = "[]" ] || [ "${raw}" = "null" ]; then
        return 0
    fi
    if printf '%s' "${raw}" | jq -e 'type == "array"' >/dev/null 2>&1; then
        printf '%s' "${raw}" | jq -r '.[]'
    else
        printf '%s\n' "${raw}"
    fi
}

# ---------------------------------------------------------------------------
# Image paste service (also serves the web UI that embeds the terminal)
# ---------------------------------------------------------------------------

# True if the user mapped this container port to a host port in the add-on's
# Network section. If the Supervisor cannot be asked, the answer is "no", which
# keeps the port closed - the sidebar panel works either way.
# DEV_DIRECT_ACCESS=1 (docker run -e, for testing without a Supervisor) forces
# it; add-on users have no way to set it.
port_is_published() {
    [ "${DEV_DIRECT_ACCESS:-0}" = "1" ] && return 0
    local host_port
    host_port="$(bashio::addon.port "$1" 2>/dev/null || true)"
    [ -n "${host_port}" ] && [ "${host_port}" != "null" ]
}
start_image_service() {
    export IMAGE_SERVICE_PORT="${WEB_PORT}"
    export TTYD_PORT="${TTYD_PORT}"
    export UPLOAD_DIR="${DATA_ROOT}/uploads"

    # The web interface is a root shell with no login of its own. Unless its
    # port has been published on purpose, it only accepts the Supervisor's
    # ingress proxy, so other add-ons on the internal network are refused.
    if port_is_published "${WEB_PORT}"; then
        export ALLOW_DIRECT_ACCESS=1
        bashio::log.warning "Port ${WEB_PORT} is published: the web interface is reachable without a Home Assistant login."
    else
        export ALLOW_DIRECT_ACCESS=0
    fi

    bashio::log.info "Starting the web interface on port ${WEB_PORT}..."
    node /opt/image-service/server.mjs 2>&1 | while IFS= read -r line; do
        bashio::log.info "[web] ${line}"
    done &

    sleep 2
    if curl -sf "http://127.0.0.1:${WEB_PORT}/health" >/dev/null 2>&1; then
        bashio::log.info "Web interface is up"
    else
        bashio::log.warning "The web interface did not answer yet; the terminal will still work."
    fi
}

# ---------------------------------------------------------------------------
# The session itself
# ---------------------------------------------------------------------------
start_terminal() {
    local auto_launch
    auto_launch="$(config_bool 'auto_launch_codex' 'true')"
    export CODEXPRO_AUTO_LAUNCH="${auto_launch}"

    if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
        bashio::log.info "Re-using the existing '${TMUX_SESSION}' session - your previous work is still there."
    else
        bashio::log.info "Creating the persistent '${TMUX_SESSION}' session..."
        tmux new-session -d -s "${TMUX_SESSION}" -c /homeassistant "/usr/local/bin/codex-menu"
    fi

    # ttyd has no login of its own either. Unless its port is published, it
    # listens on loopback only, where just the web interface's proxy reaches it.
    local interface=127.0.0.1
    if port_is_published "${TTYD_PORT}"; then
        interface=0.0.0.0
        bashio::log.warning "Port ${TTYD_PORT} is published: the terminal is reachable without a Home Assistant login."
    fi

    bashio::log.info "Terminal ready. Open the add-on panel in the sidebar."

    exec ttyd \
        --port "${TTYD_PORT}" \
        --interface "${interface}" \
        --writable \
        --ping-interval 30 \
        --client-option reconnect=5 \
        --client-option 'fontSize=14' \
        --client-option 'fontFamily=Menlo,Consolas,monospace' \
        /usr/local/bin/codex-attach
}

main() {
    bashio::log.info "Codex Pro starting..."
    init_environment
    tidy_data
    setup_config_alias
    setup_ha_access
    setup_codex_cli
    setup_ha_mcp_server
    setup_codex_config
    warm_up_ha_mcp
    setup_tmux
    setup_persistent_packages
    start_image_service
    start_terminal
}

main "$@"
