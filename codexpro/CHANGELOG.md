# Changelog

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
