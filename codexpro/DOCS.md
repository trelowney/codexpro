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

Updates are stored in `/data` and survive restarts. Home Assistant backups
leave out only the updated Codex and download caches (they can always be
downloaded again), which keeps them small - your conversations, notes and
files in `/data` are always backed up and never deleted; after restoring a backup the add-on uses the Codex built into it
until the next `codex-update` or automatic update. If an update ever installs
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
| `file_access` | `full` (default) = Codex can run commands and change files in everything the add-on sees - which is only the folders listed below. `workspace` = Codex's own extra sandbox; Home Assistant's add-on container does not allow it, so the add-on falls back to `full` and says so in the log |
| `enable_ha_mcp` | Let Codex query entities and call services |
| `openai_api_key` | Only for API-key billing; leave empty for ChatGPT sign-in |
| `auto_update_codex` | Fetch the newest Codex CLI on every start |
| `auto_update_ha_mcp` | Fetch the newest Home Assistant connection (hass-mcp) on every start |
| `tmux_mouse` | Mouse in the terminal; hold Shift to select text for copying |
| `persistent_apk_packages` | Alpine packages reinstalled after every restart |
| `persistent_pip_packages` | Python packages reinstalled after every restart |
| `voice_stt_provider` | Optional. Home Assistant speech-to-text engine for 🎤 Voice Input, for example `stt.faster_whisper`. Empty = the browser's own speech recognition |
| `voice_language` | Language you dictate in, for example `cs` or `de-DE`. Empty = the browser's language |
| `status_line` | What the bar at the bottom of the terminal says about your home. Empty = everything (see below). `off` = nothing. Or a list of pieces and entities, for example `backup`, `disk`, `CO2=sensor.living_room_co2` |

## Folders

| Path | What it is | Access |
|---|---|---|
| `/homeassistant` and `/config` | Home Assistant configuration (same folder) | read-write |
| `/addon_configs` | other add-ons' configuration | read-write |
| `/share`, `/media` | shared folders | read-write |
| `/addons` | local add-ons (your own add-on sources) | read-write |
| `/ssl`, `/backup` | certificates, backups | read-only |
| `/data` | this add-on's own storage (sign-in, sessions, updates) | read-write |
| `/data/uploads` | files you upload in the web interface | read-write |

## Uploading files

Paste (Ctrl+V or Cmd+V), drag, or pick files with 📎 **Upload** in the web
interface - a screenshot, a YAML file, a PDF manual, a log, anything up to
50 MB, several at once. Each one is saved to `/data/uploads` and its path is
typed at the prompt, so you can ask Codex about it. Pasting and dropping work
while the cursor is in the terminal too. Ctrl+V always pastes from your
computer's clipboard (text or file); it is no longer passed on to programs in
the terminal.

Uploads are kept and included in Home Assistant backups. For anything bigger
than 50 MB, put it in `/share` (for example with the Samba add-on) and give
Codex that path.

If you open Home Assistant through your own reverse proxy (NGINX, Caddy, a
tunnel), that proxy has its own upload limit and applies it first. NGINX
allows only 1 MB unless told otherwise: if bigger uploads fail with
"413 Request Entity Too Large", set `client_max_body_size 55m;` for Home
Assistant there.

## Dictating (🎤 Voice Input)

🎤 **Voice Input** in the header opens a window: press **Start Recording**,
speak, press **Stop Recording**. Check the text (you can edit it in the box),
then **Insert in Terminal** - it is typed at the prompt as one line, and you
press Enter yourself. **Copy Text** copies it instead.

Two ways of turning speech into text:

- **Home Assistant speech-to-text** (recommended, works in every browser
  including Firefox and the Home Assistant app): in the add-on Configuration
  fill in **Speech-to-text engine** with the engine's entity ID, for example
  `stt.faster_whisper` (local Whisper) or `stt.home_assistant_cloud` (Nabu
  Casa). Settings > Voice assistants shows which engines you have. Restart the
  add-on afterwards.
- **The browser's own speech recognition** when the option is empty (Chrome,
  Edge, Safari; not Firefox). The browser may send the audio to its vendor.

The microphone only works when Home Assistant is opened over **HTTPS** (an
address starting with `https://`), and the browser or the app must be allowed
to use it. One recording is at most 60 seconds. It stays in memory, goes only
to the configured Home Assistant engine and is never saved or logged; the
add-on's Home Assistant token never reaches the browser. If something is
missing, the window says what to do.

## Typing in the terminal

- **Shift+Enter** starts a new line in the prompt without sending it (it types
  Ctrl+J, which Codex reads as a new line). Ctrl+J itself does the same.
- **On a phone or tablet** a row of keys appears above the on-screen keyboard:
  **Esc** (stop Codex, close a menu), **↑ ↓** (choose in a menu, earlier
  prompts), **Tab**, **⇧Tab** (switch mode), **^C**, **⇧↵** (new line without
  sending) and **↵** (send). Two Ctrl+C in a row quit Codex, and a double tap
  is easy on a phone, so after one tap the ^C key shows *wait* for two seconds.
  The row is hidden on computers and on tablets with a trackpad.
- **Your own tmux settings** go in `/data/home/.tmux.local.conf`.
  `/data/home/.tmux.conf` is rewritten on every start, so changes there are
  lost; the local file is read last, so its settings win. Restart the add-on
  to apply them.

## Your home on the status bar

The bar at the bottom of the terminal shows **🏠 ✓** when nothing needs a look.
Otherwise it lists what does, most urgent first:

| Piece | Shows | When |
|---|---|---|
| `alerts` | 🚨 name | a smoke, gas, carbon monoxide, water or safety sensor is on (red) |
| `repairs` | 🩺 2 repairs | Home Assistant has repairs waiting, or the system is unhealthy |
| `automations` | 🤖 1 not loaded | an automation did not load (usually a YAML mistake) |
| `backup` | 💾 9 days | the last backup is over 2 days old (red over 7 days, or none at all) |
| `disk` | 💽 85% | the disk is 80 % full or more (red from 90 %) |
| `core` | ⬆ HA 2026.11.1 | a new Home Assistant version is out |
| `updates` | 📦 3 | updates are waiting (add-ons, integrations, devices) |
| `unavailable` | ⚠ 4 unavailable | entities are unavailable (a device is off or out of range) |
| `battery` | 🔋 Door lock 12% | a battery sensor is below 20 % |

**Type `ha-status` in the terminal** to see each item spelled out with what to
do about it. `ha-status --refresh` asks Home Assistant right now and says what
failed if it cannot. **🏠 ?** means Home Assistant could not be read; **🏠 …**
means the first reading is still on its way (it takes a few seconds after a
start).

To change the line, set the `status_line` option on the Configuration tab
and restart the add-on:

- leave it empty for all the pieces above;
- `off` to show nothing about the home;
- a list of pieces, in the order you want them, for example `alerts`,
  `backup`;
- any entity, alone (`sensor.living_room_co2` shows its name and value) or
  with a short label (`CO2=sensor.living_room_co2`). A misspelt entity shows
  *not found*; an unknown piece is named in the add-on log.

The line is read in the background once a minute (backups, disk and repairs
every five minutes), so it does not slow anything down. Your own tmux settings
in `/data/home/.tmux.local.conf` still win, including your own `status-right`.

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
- **± Changes** — what changed in the configuration folder since you last
  accepted it, file by file, with the exact lines added and removed. Click
  **Start tracking changes** once; it creates a local git repository in the
  configuration folder (nothing is uploaded anywhere). **↩ Revert file** puts one
  file back (click twice to confirm); **✓ Accept all changes** marks the current
  state as the new starting point. `secrets.yaml`, `.storage` and other
  sensitive files are never tracked or shown.

Apart from ↩ Revert file in ± Changes, the sidebar never changes a file.
Drag its left edge to resize it; » hides it to a thin rail. It remembers whether it was open and how wide.

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
| Codex will not write a file, or says `bwrap: ... Permission denied` | Set `file_access: full` and restart the add-on; `codex-doctor` checks whether Codex can run commands |
| A command disappeared after a restart | Install it with `persist-install`, or add it to `persistent_apk_packages` |
| Terminal shows nothing | Restart the add-on; the session is recreated on the next connection |
| MCP errors in the log | Set `enable_ha_mcp: false` — file access keeps working |
| Direct access on port 7680/7681 stopped working | Since 1.2.0 the ports are closed unless published; see Security above |
