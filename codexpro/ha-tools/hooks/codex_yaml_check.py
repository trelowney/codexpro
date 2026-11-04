#!/usr/bin/env python3
"""Codex hook: after Codex changes a YAML file, check it and tell Codex the result.

validate_ha_yaml.py (upstream, unchanged) checks one file and speaks Claude
Code's format. This adapts it to what Codex sends:

- apply_patch carries the patch text, so the paths come out of its headers.
- A shell command says nothing reliable about what it changed. The PreToolUse
  call leaves a timestamp; afterwards YAML files changed since then count, found
  in the command's text and in the folders Home Assistant reads. A plain `cat`
  of a file that was already broken is therefore not reported as an edit.
- A broken file goes back as additionalContext, never as `decision: block`:
  Codex hands a block to the model as a failed tool call, so it reports that the
  file was not written while the broken file stays on disk.

Anything unexpected exits 0 in silence. This must never get in Codex's way.
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

CHECKER = Path(__file__).resolve().parent / "validate_ha_yaml.py"
STAMPS = Path("/tmp/codexpro-yaml-check")
SCAN_ROOTS = ("/homeassistant", "/addon_configs")
# Not hand-written configuration, and some of these get very large
SKIP_DIRS = {"custom_components", "deps", "node_modules", "tts", "www", "__pycache__", "image"}
SCAN_SECONDS = 1.0
MAX_FILES = 20
TOTAL_SECONDS = 25
MAX_TEXT = 6000
# A file's mtime comes from the kernel's coarse clock, a little behind time.time()
CLOCK_SLACK = 0.05
SAVED = ("The edit above WAS saved: the file is on disk right now in this state, "
         "nothing was rejected.")
REPAIR = ("Repair it now and check again. If repairing means changing what the user "
          "asked for (two values for one key, for example), say exactly what you "
          "changed, or ask.")


def stamp_of(event):
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", str(event.get("tool_use_id") or ""))
    return STAMPS / name if name else None


def before_command(event):
    stamp = stamp_of(event)
    if stamp is None:
        return
    STAMPS.mkdir(exist_ok=True)
    stamp.write_text(str(time.time()))
    # A failed command gets no PostToolUse, so its stamp stays behind
    for old in STAMPS.iterdir():
        if time.time() - old.stat().st_mtime > 86400:
            old.unlink(missing_ok=True)


def is_yaml(name):
    return name.lower().endswith((".yaml", ".yml"))


def absolute(path, cwd):
    return path if os.path.isabs(path) else os.path.join(cwd or "/", path)


def changed_since(since, roots):
    """YAML files under the roots changed after `since`, within SCAN_SECONDS."""
    found = []
    stop = time.monotonic() + SCAN_SECONDS
    for root in roots:
        for folder, dirs, files in os.walk(root):
            if time.monotonic() > stop:
                return found
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_DIRS]
            for name in files:
                path = os.path.join(folder, name)
                if is_yaml(name) and modified_after(path, since):
                    found.append(path)
    return found


def modified_after(path, since):
    try:
        return os.stat(path).st_mtime >= since - CLOCK_SLACK
    except OSError:
        return False


def paths_from_command(event, command):
    stamp = stamp_of(event)
    if stamp is None:
        return []
    try:
        since = float(stamp.read_text())
    except (OSError, ValueError):
        return []
    stamp.unlink(missing_ok=True)
    cwd = event.get("cwd")
    named = [absolute(p, cwd) for p in re.findall(r"[^\s'\"<>|;&=()]+\.ya?ml\b", command, re.I)]
    named = [p for p in named if modified_after(p, since)]
    roots = [r for r in SCAN_ROOTS if os.path.isdir(r)]
    if cwd and os.path.isdir(cwd) and not any(os.path.realpath(cwd).startswith(os.path.realpath(r)) for r in roots):
        # Only a folder of its own: "/" would walk the whole container
        if os.path.realpath(cwd) != "/":
            roots.append(cwd)
    return named + changed_since(since, roots)


def paths_from_patch(event, patch):
    found = re.findall(r"^\*\*\* (?:Add File|Update File|Move to): (.+?)\s*$", patch, re.M)
    return [absolute(p, event.get("cwd")) for p in found if is_yaml(p)]


def check(path, cwd, deadline):
    event = {"cwd": cwd, "tool_input": {"file_path": path}}
    left = deadline - time.monotonic()
    if left <= 0:
        return None
    done = subprocess.run([sys.executable, str(CHECKER)], input=json.dumps(event),
                          capture_output=True, text=True, timeout=left)
    return json.loads(done.stdout) if done.stdout.strip() else None


def after_tool(event):
    command = (event.get("tool_input") or {}).get("command") or ""
    if isinstance(command, list):
        command = " ".join(command)
    if event.get("tool_name") == "apply_patch":
        paths = paths_from_patch(event, command)
    else:
        paths = paths_from_command(event, command)

    seen = {}
    for path in paths:
        seen.setdefault(os.path.realpath(path), path)
    paths = list(seen.values())
    if not paths:
        return

    deadline = time.monotonic() + TOTAL_SECONDS
    broken, advice = [], []
    for path in paths[:MAX_FILES]:
        result = check(path, event.get("cwd"), deadline)
        if not result:
            continue
        if result.get("decision") == "block":
            broken.append(result.get("reason") or "")
        else:
            text = (result.get("hookSpecificOutput") or {}).get("additionalContext")
            if text:
                advice.append(text)

    parts = []
    if broken:
        parts += [SAVED] + broken + [REPAIR]
    parts += advice
    if len(paths) > MAX_FILES:
        parts.append(f"Only {MAX_FILES} of the {len(paths)} changed YAML files were checked; "
                     "use the ha-check skill for the rest.")
    if not parts:
        return
    text = "\n".join(parts)
    if len(text) > MAX_TEXT:
        text = text[:MAX_TEXT] + "\n... cut short; use the ha-check skill to see everything."
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}}))


def main():
    event = json.load(sys.stdin)
    if event.get("hook_event_name") == "PreToolUse":
        before_command(event)
    elif event.get("hook_event_name") == "PostToolUse":
        after_tool(event)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
