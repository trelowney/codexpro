# Codex Pro for Home Assistant

OpenAI Codex in the Home Assistant sidebar — with the three things that made the
existing add-ons frustrating fixed:

| Problem | How it is fixed here |
|---|---|
| The session dies when Home Assistant restarts or the tab is closed | The terminal session lives in a detached `tmux` session created when the add-on starts. `ttyd` only *attaches* to it, so a dropped connection changes nothing. After an add-on restart you continue with **Continue where I left off** (`codex resume`). |
| `npm install -g @openai/codex@latest` fails with *permission denied* | Everything runs as root and the writable npm prefix is `/data/npm`, a persistent volume. `codex-update` updates the CLI from inside the terminal, and the update survives restarts. |
| Codex cannot actually change Home Assistant files (dashboards, YAML) | The mapped folders are declared as writable roots of the Codex sandbox, `/homeassistant` is pre-trusted, and `/config` is a shortcut to it — so both path styles work. |

This is a combined fork of [kecksdigital/codex-hass](https://github.com/kecksdigital/codex-hass)
and [esjavadex/claude-code-ha](https://github.com/esjavadex/claude-code-ha),
both MIT. See [ATTRIBUTION.md](ATTRIBUTION.md).

## Install

Home Assistant add-ons are **not** installed through HACS — HACS handles
integrations, cards and themes. Add-ons come from an *add-on repository*, which
is what this repository is:

1. In Home Assistant go to **Settings → Add-ons → Add-on Store**.
2. Top-right **⋮ → Repositories**.
3. Paste `https://github.com/trelowney/codexpro` and press **Add**, then **Close**.
4. Refresh the page. **Codex Pro** now appears in the store — open it and press
   **Install**.
5. Press **Start**, then **Open Web UI** (or use the sidebar entry).

Supported architectures: `amd64` and `aarch64` (the Codex CLI has no 32-bit ARM
build, so a Raspberry Pi must be running the 64-bit OS).

## First run

The panel opens into a menu. Choose **4) Sign in / switch account**:

- **Device code** (recommended) — Codex shows a short code and a web address.
  Open it on your phone or computer, type the code, approve. Nothing needs to
  reach the container.
- **API key** — paste an OpenAI API key instead (billed per use).
- **Browser link** — the classic ChatGPT sign-in; needs one copy-paste step
  because the final redirect points at `localhost:1455` *inside* the container.
- **Copy a sign-in from another computer** — drop your `~/.codex/auth.json` into
  the `share` folder as `codex-auth.json`.

The sign-in is stored in `/data/codex/auth.json` and survives restarts and
add-on updates.

## Commands inside the terminal

| Command | What it does |
|---|---|
| `codex-update` | Update the Codex CLI (`--check`, `--reset` also available) |
| `codex-login` | Sign in, switch account or sign out |
| `codex-doctor` | Self-check: sign-in, file access, API, configuration, disk |
| `ha-reload` | Validate the configuration and apply it (`--restart` for a full restart) |
| `persist-install` | Install extra apk/pip tools that survive restarts |

## Paths

| Path | What it is | Access |
|---|---|---|
| `/homeassistant`, `/config` | Home Assistant configuration (same folder) | read-write |
| `/addon_configs` | other add-ons' configuration | read-write |
| `/share`, `/media` | shared folders | read-write |
| `/ssl`, `/backup` | certificates, backups | read-only |
| `/data` | this add-on's persistent state | read-write |

UI dashboards live in `/config/.storage/lovelace*`. Home Assistant keeps them in
memory, so after editing one run `ha-reload --restart`.

## Options

Every option is explained in the add-on's Configuration tab. The short version:

- `auto_launch_codex` — jump straight into Codex instead of the menu
- `model` — leave empty unless you want a specific model
- `approval_policy` — how often Codex asks before acting (`on-request` default)
- `file_access` — `workspace` (mapped folders) or `full` (no restriction)
- `enable_ha_mcp` — let Codex query entities and call services, not just files
- `openai_api_key` — optional, only for API-key billing
- `auto_update_codex` — update the CLI on every start
- `tmux_mouse` — mouse in the terminal (breaks browser copy/paste)
- `persistent_apk_packages`, `persistent_pip_packages` — extra tools to keep

## Something is wrong

Run `codex-doctor` in the terminal. Every failed check tells you what to do.
If you open an issue, paste that output into it.

## License

MIT — see [LICENSE](LICENSE).
