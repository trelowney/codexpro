#!/usr/bin/env python3
"""Refresh codexpro/ha-tools from ESJavadex/claude-homeassistant-plugins (MIT).

    python3 scripts/import-ha-tools.py v2.1.3

Copies the skills and the YAML validator, and rewrites what only makes sense in
Claude Code. The checker itself stays as upstream wrote it. Nothing here touches
hooks/codex_yaml_check.py or hooks.json, which are ours. Then read the diff.
"""
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

REPO = "ESJavadex/claude-homeassistant-plugins"
TARGET = Path(__file__).resolve().parent.parent / "codexpro" / "ha-tools"
OPT = "/opt/codexpro-ha"
# Written by hand in Claude's front matter; Codex only reads name and description.
DROP_KEYS = ("allowed-tools", "argument-hint", "disable-model-invocation")


def front_matter(text, path):
    """Keep name and description, fold when_to_use into the description."""
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        sys.exit(f"{path}: no front matter")
    lines = [l for l in match.group(1).split("\n") if l.split(":")[0] not in DROP_KEYS]
    when = [l for l in lines if l.startswith("when_to_use:")]
    lines = [l for l in lines if not l.startswith("when_to_use:")]
    if when:
        extra = when[0].split(":", 1)[1].strip()
        lines = [l + " " + extra if l.startswith("description:") else l for l in lines]
    description = next(l for l in lines if l.startswith("description:"))
    if len(description) - len("description: ") > 1024:
        sys.exit(f"{path}: description over Codex's 1024 characters")
    return "---\n" + "\n".join(lines) + "\n---\n" + text[match.end():]


def to_codex(text):
    text = text.replace("${CLAUDE_PLUGIN_ROOT}", OPT)
    text = text.replace("${CLAUDE_SKILL_DIR}", f"{OPT}/skills/homeassistant-config")
    text = text.replace("`$ARGUMENTS`", "what the user named")
    text = text.replace(".claude-backups", ".codex-backups")
    text = text.replace("in the Claude Terminal\n   add-on `ha core info`", "in this\n   add-on `ha core info`")
    text = re.sub(r"(?<![\w/.-])/(ha-(?:check|upgrade|find-duplicates))\b", r"$\1", text)
    text = re.sub(r"\n[^\n]*`ha-suggestions` agent[^\n]*", "", text)
    text = text.replace("A plugin hook checks", "A hook checks")
    text = text.replace("comes back as a block: fix it at once", "comes back as a message right after the edit: fix it at once")
    text = text.replace("this plugin's history", "older guides")
    text = text.replace("Commands in this plugin:", "Skills in this add-on:")
    text = text.replace("with this plugin:", "with the add-on's checkers:")
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    tag = sys.argv[1]
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        url = f"https://github.com/{REPO}/archive/refs/tags/{tag}.tar.gz"
        with urllib.request.urlopen(url, timeout=60) as response:
            (tmp / "a.tgz").write_bytes(response.read())
        with tarfile.open(tmp / "a.tgz") as archive:
            archive.extractall(tmp, filter="data")
        root = next(p for p in tmp.iterdir() if p.is_dir())
        plugin = root / "homeassistant-config"

        shutil.rmtree(TARGET / "skills", ignore_errors=True)
        shutil.copytree(plugin / "skills", TARGET / "skills",
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        (TARGET / "hooks").mkdir(parents=True, exist_ok=True)
        shutil.copy(plugin / "hooks" / "validate_ha_yaml.py", TARGET / "hooks")
        shutil.copy(root / "LICENSE", TARGET / "LICENSE.upstream")
        (TARGET / "UPSTREAM").write_text(f"https://github.com/{REPO} {tag}\n")

    for path in (TARGET / "skills").rglob("*.md"):
        text = to_codex(path.read_text())
        if path.name == "SKILL.md":
            text = front_matter(text, path)
        path.write_text(text)

    # A big rewrite only when asked for, as upstream's disable-model-invocation.
    policy = TARGET / "skills" / "ha-upgrade" / "agents" / "openai.yaml"
    policy.parent.mkdir(exist_ok=True)
    policy.write_text("policy:\n  allow_implicit_invocation: false\n")

    left = [str(p.relative_to(TARGET)) for p in (TARGET / "skills").rglob("*.md")
            if re.search(r"CLAUDE_|ARGUMENTS|Claude Terminal|ha-suggestions", p.read_text())]
    if left:
        sys.exit(f"Claude-only wording left in: {left}")


if __name__ == "__main__":
    main()
