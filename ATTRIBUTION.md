# Attribution

Codex Pro is a combined fork of two MIT-licensed Home Assistant add-ons. Both
are excellent starting points; this project merges what each does best and fixes
the parts that got in the way of daily use.

## kecksdigital/codex-hass

<https://github.com/kecksdigital/codex-hass> — MIT, © 2025 Robson Felix

Taken from it:

- the idea of running the OpenAI Codex CLI as a Home Assistant panel add-on
- the Home Assistant MCP server integration (`hass-mcp`) and its wrapper
- the managed-merge approach to `config.toml`, including the repair logic for
  configuration files that older Codex builds left unparseable
  (`codex-merge-config`)
- the model / approval-policy / file-access add-on options
- the generated `AGENTS.md` that explains the container's path layout to Codex

## esjavadex/claude-code-ha

<https://github.com/esjavadex/claude-code-ha> — MIT, © 2025 Javier Santos
(itself a fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons))

Taken from it:

- the persistent-session architecture: a detached `tmux` session created at
  add-on start, with `ttyd` only attaching to it
- keeping all state (`HOME`, XDG directories, credentials) on the `/data`
  volume so it survives restarts and add-on updates
- the persistent global npm prefix that makes the CLI updatable from inside the
  container
- `persist-install` for extra apk/pip packages that survive restarts
- the image-paste web interface (`image-service/`)

## What is new here

- Codex sessions survive a browser reload, an ingress drop and a Home Assistant
  Core restart, and can be resumed after an add-on restart via `codex resume`
- the Codex CLI updates from inside the container without any permission errors,
  because the add-on runs as root and installs into a writable persistent prefix
- Home Assistant folders are declared as writable roots of the Codex sandbox and
  `/config` is a shortcut to `/homeassistant`, so Codex can actually edit
  dashboards, YAML and other add-ons' configuration
- sign-in helper covering device-code, API key, browser-link and copied
  `auth.json` flows (`codex-login`)
- `codex-doctor` self-check and `ha-reload` helper
