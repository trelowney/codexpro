# Codex Pro

OpenAI Codex in a terminal that has access to your Home Assistant configuration.
You describe what you want in plain language; Codex reads and edits the files.

## Before you start

You need one of:

- a ChatGPT **Plus**, **Pro** or **Business** account, or
- an **OpenAI API key** (billed per use).

## First start

1. Press **Start**, wait a few seconds, then open the **Codex Pro** panel in the
   sidebar.
2. The welcome screen offers a sign-in. Pick **Device code** — you get a short
   code and a web address, you open that address on your phone or computer,
   type the code, done.
3. Back in the panel choose **1) Start a new Codex session** and type what you
   want, for example:
   *"add an automation that turns the porch light on at sunset"*.

## The session keeps running

Closing the browser tab, reloading it or restarting Home Assistant does **not**
end your session. Come back to the panel and you are exactly where you left off.

After the *add-on itself* restarts (an update, a host reboot), choose
**2) Continue where I left off** to pick your conversation back up.

## After Codex changes something

- YAML change → run `ha-reload`
- UI dashboard change (`/config/.storage/lovelace*`) → run `ha-reload --restart`

`ha-reload` validates the configuration first and applies nothing if it is
broken.

## Keeping Codex up to date

Two separate things:

- **The add-on** updates through Settings → Add-ons, like any other add-on.
- **The Codex CLI** inside it updates with `codex-update` in the terminal, or
  automatically on every start if you switch on `auto_update_codex`.

Updates are stored in `/data` and survive restarts.

## Options

| Option | Meaning |
|---|---|
| `auto_launch_codex` | Open straight into Codex instead of the menu |
| `model` | Empty = the Codex default. Only fill in a model you know exists |
| `approval_policy` | `on-request` (default), `untrusted`, `on-failure`, `never` |
| `file_access` | `workspace` = mapped folders (default), `full` = no restriction |
| `enable_ha_mcp` | Let Codex query entities and call services |
| `openai_api_key` | Only for API-key billing; leave empty for ChatGPT sign-in |
| `auto_update_codex` | Fetch the newest Codex CLI on every start |
| `tmux_mouse` | Mouse in the terminal; breaks browser copy/paste |
| `persistent_apk_packages` | Alpine packages reinstalled after every restart |
| `persistent_pip_packages` | Python packages reinstalled after every restart |

## Folders

| Path | What it is | Access |
|---|---|---|
| `/homeassistant` and `/config` | Home Assistant configuration (same folder) | read-write |
| `/addon_configs` | other add-ons' configuration | read-write |
| `/share`, `/media` | shared folders | read-write |
| `/ssl`, `/backup` | certificates, backups | read-only |
| `/data` | this add-on's own storage (sign-in, sessions, updates) | read-write |

## Images

Paste or drag an image into the web interface. It is saved to `/data/images` and
its path is typed into the terminal, so you can ask Codex about a screenshot of
your dashboard.

## Troubleshooting

Run `codex-doctor` in the terminal. It checks the sign-in, file access, the
Home Assistant API, the Codex configuration file, the session and free disk
space, and each failed check says what to do about it.

| Symptom | Do this |
|---|---|
| "not signed in" | `codex-login`, option 1 |
| Codex will not write a file | Set `file_access: full` and restart the add-on |
| A command disappeared after a restart | Install it with `persist-install`, or add it to `persistent_apk_packages` |
| Terminal shows nothing | Restart the add-on; the session is recreated on the next connection |
| MCP errors in the log | Set `enable_ha_mcp: false` — file access keeps working |
