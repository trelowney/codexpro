# Changelog

## [1.7.2] - 2026-11-06

The terminal reconnects by itself, and every start checks space, memory and the connection.

### Fixed

- **The terminal comes back by itself after sleep, a network drop or a Home
  Assistant restart.** ttyd tries once, straight away, and then stops at "Press ⏎
  to Reconnect". That try often came too early and Enter failed the same way, so
  only leaving the page and coming back helped. While that message shows, the panel
  now asks the add-on if it is reachable after 1, 2 and 5 s, then every 10 s, and at
  once when the browser is back online or the tab is shown again. When the add-on
  answers, the terminal reloads into the same session
- **The panel says what is going on** next to the title while it reconnects
- Each try is logged in the browser console as `[terminal-reconnect]`
- Removed ttyd's `--client-option reconnect=5`: ttyd 1.7.7 has no such option

### Added

- **A short check at every start.** One line in the log gives free space, free
  memory and whether OpenAI can be reached. If `/data` cannot be written to, or
  space, memory or the connection is a problem, a warning says what to do

## [1.7.1] - 2026-11-04

Dashboard findings say where they are.

### Changed

- **Dashboard findings name what you see in the editor.** Dashboards built in the
  UI have no line numbers, so a finding only gave a path like
  `views[1].sections[1].cards[0]`. It now also gives the view title and tab, the
  section heading, and the card number and type, for example
  `view "Living Room" (tab 2) > section "Lights" > card 2 (tile)`

### Fixed

- **A new empty sections view gets no warning**: the UI editor writes `cards: []`
  on every new one

The skills and the checks are now at
[ESJavadex/claude-homeassistant-plugins](https://github.com/ESJavadex/claude-homeassistant-plugins) v2.1.4.

## [1.7.0] - 2026-11-04

Codex checks the YAML it writes, and knows current Home Assistant.

### Added

- **Every YAML file Codex changes is checked right away**: syntax, tabs, duplicate
  keys, and syntax your Home Assistant version no longer accepts. Codex is told at
  once and repairs a broken file in the same answer. Works for its own edits and
  for shell commands
- **Home Assistant skills.** Codex can read a guide to current syntax before
  writing configuration. Say "check my configuration" or type `$ha-check`;
  `$ha-find-duplicates` and `$ha-upgrade` are there too
- **Option `home_assistant_tools`** (on by default) turns all of it off.
  `codex-doctor` tries the check on a broken file and reports the result

Your files in `/data` are not touched. The skills and the checks come from
[ESJavadex/claude-homeassistant-plugins](https://github.com/ESJavadex/claude-homeassistant-plugins) (MIT).

## [1.6.3] - 2026-11-04

An old update no longer pins Codex, and a quieter status bar.

### Fixed

- **An old `codex-update` no longer keeps an old Codex in use for good.** A copy
  in `/data` comes first, and updating the add-on did not touch it. At every
  start, a copy older than the add-on's, or one that does not run, is now
  removed and the add-on's Codex is used. A copy that is newer is kept. Only
  that copy is removed: your files and notes in `/data`, and other npm tools,
  stay as they are
- **A battery that has not reported for a day is not shown as low**: a parked
  car keeps its last level for days
- **"No current backup" no longer counts as a repair**: the Supervisor raises it
  when backups skip a folder, with nothing to fix in the UI, and the 💾 piece
  already shows the backup's age

### Changed

- **`unavailable` is no longer on the bar by default.** Devices that turn off on
  their own (a coffee machine, a TV) kept it counting. Add `unavailable` to the
  `status_line` option to get it back
- **A single repair says what it is**: 🩺 multiple data disks instead of 🩺 1 repair

### Added

- **Leave entities out of the bar** with a minus in the `status_line` option:
  `-switch.coffee_machine` or `-sensor.car_*`. On their own they keep the default
  line
- **The Info page** has a screenshot, a link to the full guide, and lists the
  status bar and the phone keys

## [1.6.2] - 2026-11-03

A clean add-on log.

### Fixed

- **"s6-rc-compile: warning: source /etc/s6-overlay/s6-rc.d is empty"** in
  the add-on log at every start. Harmless (the base image ships that folder
  empty), now gone

## [1.6.1] - 2026-11-03

Codex's usage limits on the status bar, and no more warning at Codex's start.

### Added

- **Codex's usage limits on the terminal's status bar**, before the home:
  `⏱ 5h 62% left ↻14:30 · 7d 80% left ↻Fri 09:00` - how much of the 5-hour and the weekly
  limit is left (as Codex itself shows it), and when each resets. Yellow at
  25 % left, red at 10 % left.
  Codex writes them down with every answer, so they are as of its last answer
  here; nothing is shown before the first one or with an API key. `ha-status`
  spells them out. They are the new `limits` piece of the `status_line` option,
  on by default; list the pieces without `limits` to hide them

### Fixed

- **"Codex is ignoring 1 unrecognized configuration setting: `__codexpro`"**
  at every Codex start. The add-on kept a note of what it had written in
  `config.toml`; the note now lives in `/data/codex/codexpro-managed.json`, and
  the old table is removed on the first start. Nothing you set in Codex
  changes
- **Codex did not start at all with the approval mode `untrusted`.** Codex
  0.166 retired it (`approval_policy = "untrusted" is no longer supported`).
  The add-on now uses `on-request` instead, which still asks before risky
  steps, says so in its log, and fixes a `config.toml` that still has it
  (a copy is kept as `config.toml.repaired.bak`). The option still accepts
  the old value, so saved settings stay valid

## [1.6.0] - 2026-11-03

Your home on the terminal's status bar.

### Added

- **Home status line** at the bottom of the terminal: just 🏠 ✓ when all is
  well, otherwise what needs a look - a smoke, gas or water alarm, repairs, an
  automation that did not load, an old or missing backup, a nearly full disk,
  a new Home Assistant version, waiting updates, unavailable entities and low
  batteries. Type `ha-status` in the terminal for the details and what to do
  about each. It is read in the background once a minute (backups, disk and
  repairs every five minutes), so the bar itself costs nothing
- **Option `status_line`** to choose what the line shows: `off`, only some
  pieces (for example `backup`, `disk`), or your own entities such as
  `sensor.living_room_co2` or `CO2=sensor.living_room_co2`. Your own
  `/data/home/.tmux.local.conf` still wins
- `codex-doctor` checks the home status line too

### Fixed

- **The add-on reported no version** in its `/health` answer; it now says
  which version is running

### Changed

- Build metadata (base image, labels, version) now lives in the Dockerfile
  instead of the deprecated `build.yaml`, as Home Assistant asks. The base is
  still Python 3.13 on Alpine 3.24, so packages you installed keep working.
  Each release now checks that both the amd64 and the arm64 image carry the
  right version

## [1.5.0] - 2026-11-02

Easier on a phone, and no more stuck terminal or failed big uploads.

### Added

- **Keys for a phone or tablet**: a row above the on-screen keyboard with
  Esc, ↑, ↓, Tab, ⇧Tab, ^C, a new-line key and Enter - the keys Codex needs
  for stopping, menus and multi-line prompts, which a phone keyboard lacks.
  Tapping one keeps the keyboard open. ^C waits two seconds after a tap,
  because two in a row quit Codex. Shown only when a touch screen is the
  main pointer. Arrows also work in full-screen programs such as less and vim
- **Shift+Enter starts a new line** in the prompt instead of sending it
- **Your own tmux settings** in `/data/home/.tmux.local.conf`, kept across
  restarts and read last so they win. tmux now passes focus events through

### Fixed

- **"Failed to connect to terminal" right after starting**: the panel opened
  before the terminal was up and stayed on that message until you left the
  page. It now shows "Starting the terminal…" and continues by itself as soon
  as the terminal is ready; if that takes unusually long it says what to do
- **Uploads between 16 MB and 50 MB failed** in the panel: Home Assistant
  turned them away before they reached the add-on. They are now streamed
  through. DOCS explain the extra limit of a reverse proxy
- **After an update the browser could keep running the old panel** until a
  forced refresh (hard to do in the Home Assistant app). The page now always
  checks for a newer version
- **Ctrl+C at the Codex Pro menu ended the session**: the terminal went
  blank for a few seconds and came back as a new one. Now the menu (or the
  welcome screen) stays and asks its question again. Ctrl+C inside Codex
  works as before
- The **Network** tab now shows the full warning for ports 7680 and 7681
  (no login, root shell); before, Home Assistant showed only a short label

### Changed

- The build checks that every option and port has a name and help text in
  every language, so a new option can't appear as a raw key

Ideas from esjavadex/claude-code-ha 2.4.1-2.4.6.

## [1.4.0] - 2026-11-01

Dictation through Home Assistant, and a supported base system.

### Added

- **Dictate with Home Assistant's speech-to-text** (🎤 Voice Input): set
  **Speech-to-text engine** (`voice_stt_provider`, for example
  `stt.faster_whisper`) and dictation works in every browser, including
  Firefox and the Home Assistant app, which have no speech recognition of
  their own. Record up to 60 seconds, check and edit the text, then
  **Insert in Terminal** (one line, control characters removed, Enter is
  never pressed) or **Copy Text**. The speech language can be set
  (`voice_language`) or changed in the window. Audio stays in memory and goes
  only to that engine; the token never reaches the browser. Without the
  option, the browser's own speech recognition is used as before
- Every message in the voice window says what to do next; the record button
  is never greyed out

### Changed

- **Alpine Linux 3.24** base: 3.21 reached end of life on 1 November 2026 and
  gets no more security fixes. Node.js 24, tmux 3.7c, OpenSSL 3.5. Packages
  are upgraded at build time, so fixes released after the base image are in
- **Python stays 3.13** on purpose: the Home Assistant connection kept up to
  date in `/data` (`auto_update_ha_mcp`, `mcp-update`) and packages from
  `persist-install --python` keep working without being reinstalled
- Programs copied by `persist-install` from an older Alpine release can no
  longer shadow the system's own libraries; after the move to 3.24 the log
  names them once, in case one needs `persist-install <name>` again. Nothing
  is deleted
- No more bashio deprecation warnings in the log

## [1.3.1] - 2026-10-31

### Fixed

- **Codex could not run any command** (not `ha-api`, not even `ls`) with
  `file_access: workspace`: Home Assistant's add-on container does not allow
  Codex's sandbox (`bwrap: Failed to make / slave: Permission denied`). This
  was the case in 1.2.x too. The add-on now tries one command at start the
  way Codex runs them; if the sandbox cannot work, it uses full access and
  says so in the log. The add-on container itself still keeps Codex to the
  mapped folders
- `codex-doctor` now checks that Codex can actually run commands

### Changed

- `file_access` defaults to `full` for new installations

## [1.3.0] - 2026-10-31

Upload any file, see and undo what changed, smaller backups.

### Added

- **Upload any file**, not just images: 📎 Upload (several at once), paste or
  drop a YAML file, PDF, log or anything else up to 50 MB. Files go to
  `/data/uploads` and their path is typed at the prompt. A file that is too
  big gets advice on what to do instead
- **± Changes** in the files sidebar: what changed in the configuration folder
  since you last accepted it, with the lines added and removed; revert one
  file or accept everything. Uses a local git repository in the configuration
  folder; `secrets.yaml`, `.storage` and other sensitive files are never
  tracked or shown
- **`/addons`** (local add-ons) is now available to Codex, read-write

### Changed

- **Smaller Home Assistant backups**: only downloaded programs are left out -
  the Codex update and the npm/pip download caches, which no longer live in
  `/data` at all (the 1.2.x ones are removed at start). Your conversations,
  notes, uploads and settings stay in every backup and are never deleted.
  After restoring a backup the Codex built into the add-on is used until the
  next update
- Codex CLI 0.166.0 (was 0.164.0)
- Home Assistant MCP server `hass-mcp` 0.6.1 (was 0.6.0)

### Fixed

- In the Home Assistant mobile app the on-screen keyboard no longer covers the
  prompt

## [1.2.2] - 2026-10-24

### Security

- Rebuilt on Node.js 22.23.4 from Alpine 3.21 on both amd64 and aarch64,
  which fixes the Node.js security release of 2026-10-21 (including a Brotli
  out-of-bounds write and TLS hostname check bypasses)

### Changed

- Codex CLI 0.164.0 (was 0.163)

## [1.2.1] - 2026-10-16

### Fixed

- With `approval_policy: never`, every Home Assistant tool was refused ("MCP
  tool call requires approval, but approval policy is never") - even just
  reading a dashboard. Newer Codex asks before each of these tools, and in
  `never` mode there is nobody to ask. In that mode they are now allowed,
  exactly as the API helpers already were. Any other mode keeps asking, and a
  `default_tools_approval_mode` you set yourself in `config.toml` wins
- When a Home Assistant tool fails, Codex is told to do the same through
  `ha-api` / `ha-ws` instead of giving up

## [1.2.0] - 2026-10-16

Copying and pasting that actually work, a files sidebar, and a terminal that
only the sidebar panel can reach.

### Added

- **Files sidebar** (🗂️ Files in the header): the configuration folder as a
  tree with a read-only preview, the files changed in the last hour, day or
  week, and a button that runs Home Assistant's configuration check. Insert
  path types a file's path at the prompt. Resizable, hides to a thin rail,
  and remembers both
- **📋 Copy** in the header: the terminal text in a box you can copy from,
  which is the only way to copy on a phone or tablet
- **🔗 Copy link** appears whenever a link is on screen and copies exactly
  that link, even when it is wrapped over several lines

### Fixed

- Codex 0.163 and newer did not start at all ("failed to record pid-managed
  app-server process ... rerun with --no-daemon"). It needs a full `ps`
  command, which the add-on now includes. If you already updated Codex from
  the menu and it stopped working, this update fixes it - nothing else to do
- Selecting text with the mouse copied nothing, although a ✂ confirmation
  appeared. The selection is now really copied, and ✂ only shows when it was
- Pasting an image did nothing while the cursor was in the terminal, and
  Ctrl+V reached Codex as a request to read the container's (empty)
  clipboard. Ctrl+V now pastes from your computer — an image is uploaded and
  its path typed at the prompt, text is pasted as text
- After Codex crashed, the menu could look frozen (Enter not recognised,
  nothing echoed). The menu now resets the terminal every time it is shown
- An uploaded image's file extension came from the browser's file name; it
  now comes from the actual image type

- The first start after installing or updating could report `MCP startup
  interrupted. The following servers were not initialized: homeassistant`.
  Nothing was broken — Codex simply started before the MCP server had finished
  coming up, and the next start had it — but it looked alarming. The server is
  now warmed up in the background before Codex is launched, and it is given an
  explicit 60-second start-up window (`startup_timeout_sec`) so a slow disk or
  a small ARM board cannot run out of time either. Set `startup_timeout_sec`
  yourself in `config.toml` and your value is kept

### Security

- The terminal (a root shell with no login of its own) could be reached by
  other add-ons on Home Assistant's internal network. It now accepts only the
  sidebar panel, unless you deliberately give port 7680 or 7681 a number in
  the add-on's Network section — in which case it behaves as before
- Web interface libraries updated: `multer` 1.x → 2.x (known
  denial-of-service flaws in 1.x) and `http-proxy-middleware` 2.x → 4.x

## [1.1.0] - 2026-08-06

Direct access to the Home Assistant API, and an MCP server that can be updated
like everything else here.

### Added

- `ha-api`: the Home Assistant REST API from the terminal, already
  authenticated with the add-on's own token — states, services, templates,
  the error log, and the Supervisor API with `--supervisor`
- `ha-ws`: the WebSocket API, which is the only way to reach UI dashboards
  (`lovelace/config`, `lovelace/config/save`) and the area, device and entity
  registries
- `mcp-update`: updates `hass-mcp` into persistent storage without waiting for
  a new add-on release, with `--check` (compares against PyPI and reports how
  many tools the server offers) and `--reset`. A broken update rolls back to
  the version built into the image on its own
- `auto_update_ha_mcp` option, the MCP counterpart of `auto_update_codex`
- `AGENTS.md` now documents all three routes into Home Assistant — files, MCP
  tools and the API helpers — with worked examples, so Codex uses the API
  instead of stopping at "I only have the files"

### Changed

- `hass-mcp-wrapper` prefers an updated copy in `/data` over the built-in one
- `codex-doctor` reports the `hass-mcp` version in use and where it came from

## [1.0.0] - 2026-08-06

First release. A combined fork of `kecksdigital/codex-hass` and
`esjavadex/claude-code-ha`.

### Added

- Persistent terminal session: a detached `tmux` session is created when the
  add-on starts and `ttyd` only attaches to it, so closing the tab, an ingress
  drop or a Home Assistant Core restart no longer kills a running Codex session
- Menu with **Continue where I left off** / **Pick an earlier session**, backed
  by `codex resume` and a `CODEX_HOME` that lives on `/data`
- `codex-update`: updates the Codex CLI from inside the container into the
  persistent `/data/npm` prefix, with `--check` and `--reset`
- `codex-login`: device-code, API-key, browser-link and copied-`auth.json`
  sign-in flows, each with its own failure guidance
- `codex-doctor`: self-check for sign-in, file access, Home Assistant API,
  configuration file, session and disk space
- `ha-reload`: validates the configuration, then reloads or restarts Core
- `persist-install` and `persistent_apk_packages` / `persistent_pip_packages`
  for tools that survive restarts
- Image paste web interface on the ingress port
- Home Assistant MCP server (`hass-mcp`), optional via `enable_ha_mcp`
- Czech and English translations of every add-on option

### Changed compared to the upstream projects

- Runs as root inside the container (`IS_SANDBOX=1`), which removes the
  permission errors when updating the CLI and when writing to mapped folders
- `/homeassistant`, `/addon_configs`, `/share`, `/media` and `/data` are
  declared as writable roots of the Codex sandbox; `/homeassistant` is
  pre-trusted so no trust prompt blocks a first-time user
- `/config` is created as a shortcut to `/homeassistant`, so instructions
  written for Home Assistant Core work unchanged
- Sign-in, sessions, CLI updates and extra packages all live on `/data` and
  survive add-on updates
