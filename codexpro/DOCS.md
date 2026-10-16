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

Three separate things:

- **The add-on** updates through Settings → Add-ons, like any other add-on.
- **The Codex CLI** inside it updates with `codex-update` in the terminal, or
  automatically on every start if you switch on `auto_update_codex`.
- **The Home Assistant connection** (`hass-mcp` — this is what lets Codex read
  entities, call services and edit UI dashboards) updates with `mcp-update`, or
  automatically with `auto_update_ha_mcp`. It gains new abilities often, and an
  out-of-date one is the usual reason Codex "cannot" do something with
  dashboards. `mcp-update --check` tells you where you stand.

Updates are stored in `/data` and survive restarts. If an update ever installs
something broken, both commands detect it, roll back to the version built into
the add-on, and tell you — the add-on does not end up unusable.

## Talking to Home Assistant, not just to its files

Codex has three ways in, and it picks whichever fits:

1. the files in `/config`,
2. the MCP tools (entities, services, history, dashboards),
3. two API commands, already authenticated — no token to set up:

```bash
ha-api GET /api/states                    # every entity and its state
ha-api POST /api/services/light/turn_on '{"entity_id":"light.kitchen"}'
ha-api --supervisor GET /addons/self/info # the Supervisor API
ha-ws lovelace/dashboards/list            # UI dashboards (REST cannot do these)
ha-ws config/area_registry/list
```

Both print examples with `--help`. You will not normally type them yourself —
they exist so Codex can reach everything the API exposes when no MCP tool
covers what you asked for.

## Options

| Option | Meaning |
|---|---|
| `auto_launch_codex` | Open straight into Codex instead of the menu |
| `model` | Empty = the Codex default. Only fill in a model you know exists |
| `approval_policy` | `on-request` (default), `untrusted`, `on-failure`, `never`. With `never`, Codex uses the Home Assistant tools without asking; otherwise it asks before each one (answer "Allow for this session" to stop the questions) |
| `file_access` | `workspace` = mapped folders (default), `full` = no restriction |
| `enable_ha_mcp` | Let Codex query entities and call services |
| `openai_api_key` | Only for API-key billing; leave empty for ChatGPT sign-in |
| `auto_update_codex` | Fetch the newest Codex CLI on every start |
| `auto_update_ha_mcp` | Fetch the newest Home Assistant connection (hass-mcp) on every start |
| `tmux_mouse` | Mouse in the terminal; hold Shift to select text for copying |
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

Paste (Ctrl+V or Cmd+V), drag, or pick an image with 📎 in the web interface.
It is saved to `/data/images` and its path is typed at the prompt, so you can
ask Codex about a screenshot of your dashboard. Pasting works while the cursor
is in the terminal too. Ctrl+V always pastes from your computer's clipboard
(text or image); it is no longer passed on to programs in the terminal.

## Copying text out of the terminal

- **With a mouse:** select the text; it is copied as soon as you let go (a
  small ✂ confirmation appears). If Codex has taken the mouse, hold Shift while
  selecting.
- **📋 Copy** in the header opens the terminal text in a box: copy all of it,
  or long-press to select a part. This is the way on a phone or tablet.
- **🔗 Copy link** appears whenever a link is on screen (for example the
  sign-in link) and copies just that link, even when it is wrapped over
  several lines.

Over plain `http://` some browsers refuse automatic copying; the 📋 button
still works there because it is a click.

## Files sidebar

**🗂️ Files** in the header opens a sidebar on the right with:

- **Files** — the Home Assistant configuration folder as a tree. Click a file
  to preview it (read-only), then **Insert path** types its path at the prompt
  so you can ask Codex about it.
- **Recent changes** — files changed in the last hour, day or week, newest
  first. Handy for seeing what Codex just edited.
- **✓ Check HA configuration** — runs Home Assistant's configuration check and
  shows the result.

The sidebar never changes a file. Drag its left edge to resize it; » hides it
to a thin rail. It remembers whether it was open and how wide.

## Security

The terminal is a root shell with no login of its own, so by default it is
reachable **only through the sidebar panel**, which requires a Home Assistant
administrator login. Other add-ons on the internal network cannot connect to
it.

The add-on's Network section lists ports 7680 (web interface) and 7681
(terminal). They are off by default and the panel does not need them. If you
give one a port number, anyone who can reach that port gets the root shell
**without any login** — only do that on a network you trust completely, and
restart the add-on afterwards.

## Troubleshooting

Run `codex-doctor` in the terminal. It checks the sign-in, file access, the
Home Assistant API, the Codex configuration file, the session and free disk
space, and each failed check says what to do about it.

| Symptom | Do this |
|---|---|
| "not signed in" | `codex-login`, option 1 |
| Codex says it cannot edit a UI dashboard | `mcp-update`, then start a new session — the dashboard tools are newer than some releases |
| Codex will not write a file | Set `file_access: full` and restart the add-on |
| A command disappeared after a restart | Install it with `persist-install`, or add it to `persistent_apk_packages` |
| Terminal shows nothing | Restart the add-on; the session is recreated on the next connection |
| MCP errors in the log | Set `enable_ha_mcp: false` — file access keeps working |
| Direct access on port 7680/7681 stopped working | Since 1.2.0 the ports are closed unless published; see Security above |
