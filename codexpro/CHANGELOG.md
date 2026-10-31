# Changelog

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
