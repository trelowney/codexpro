# Codex Pro for Home Assistant

OpenAI Codex in your Home Assistant sidebar. You describe what you want in plain
language — "add an automation that turns the porch light on at sunset", "why does
my heating script never fire?" — and Codex reads and edits the actual files in
your configuration.

**Fork attribution:** this is a combined fork of
[kecksdigital/codex-hass](https://github.com/kecksdigital/codex-hass) by Robson
Felix and [esjavadex/claude-code-ha](https://github.com/esjavadex/claude-code-ha)
by Javier Santos, both MIT licensed.

## What is different here

Three things about the existing Codex add-on made it painful. All three are fixed:

- **The session no longer dies.** The terminal lives in a detached `tmux` session
  created when the add-on starts; the browser only *attaches* to it. Close the
  tab, reload it, restart Home Assistant — you come back to exactly where you
  were. After the add-on itself restarts, **Continue where I left off** picks the
  conversation back up.
- **The CLI updates from inside the container.** No more *permission denied*:
  `codex-update` in the terminal installs the newest Codex into `/data/npm`,
  which is persistent, so the update survives restarts as well.
- **Codex can really change your configuration.** The mapped folders are declared
  as writable roots of the Codex sandbox, `/homeassistant` is pre-trusted, and
  `/config` is a shortcut to the same folder — so dashboards, YAML and scripts
  are all editable.

## Features

- **Sidebar panel** — no separate port, no extra login, ingress only.
- **Menu instead of a bare prompt** — new session, resume a previous one, sign
  in, update, self-check. Every error says what to do about it.
- **Four ways to sign in** — device code (recommended), API key, browser link, or
  copying an existing `auth.json` from another computer. The sign-in is stored in
  `/data` and survives updates.
- **Home Assistant MCP** — Codex can query entities and call services, not just
  read files.
- **`ha-reload`** — validates the configuration and applies it without a full
  restart (`--restart` when you changed a UI dashboard).
- **`persist-install`** — extra Alpine and Python packages that survive restarts.
- **Image paste** — drop a screenshot into the web interface and ask about it.
- **`codex-doctor`** — one command that checks sign-in, file access, the API, the
  configuration file, the session and free disk space.

## What you need

A ChatGPT **Plus**, **Pro** or **Business** account, or an **OpenAI API key**
(billed per use). Architectures: `amd64` and `aarch64` — the Codex CLI publishes
no 32-bit ARM build, so a Raspberry Pi needs the 64-bit OS.

## Getting started

Press **Start**, open the **Codex Pro** panel in the sidebar, and choose
**4) Sign in / switch account** → **Device code**. You get a short code and a web
address; open it on your phone, type the code, done.

The **Documentation** tab has the rest: first run, what to do after Codex changes
something, every option explained, folder access and troubleshooting.

## Folders

| Path | What it is | Access |
|---|---|---|
| `/homeassistant`, `/config` | Home Assistant configuration (same folder) | read-write |
| `/addon_configs` | other add-ons' configuration | read-write |
| `/share`, `/media` | shared folders | read-write |
| `/ssl`, `/backup` | certificates, backups | read-only |
| `/data` | this add-on's storage (sign-in, sessions, updates) | read-write |

## Support

Run `codex-doctor` in the terminal first — it names the problem and the fix. If
that is not enough, open an issue at
<https://github.com/trelowney/codexpro/issues> and paste that output in.

MIT licensed.
