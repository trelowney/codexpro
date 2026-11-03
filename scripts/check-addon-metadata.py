#!/usr/bin/env python3
"""Fail when an add-on option or port has no label and help text.

Home Assistant shows the Configuration and Network tabs from
codexpro/translations/<lang>.yaml. An option missing there appears as its raw
key (auto_update_ha_mcp) with no explanation, which nobody but the author
understands. Every language file must name and describe every option in
config.yaml's schema, and describe every port.

Run from the repository root: python3 scripts/check-addon-metadata.py
"""
import pathlib
import sys

import yaml

ADDON = pathlib.Path(__file__).resolve().parent.parent / "codexpro"


def main() -> int:
    config = yaml.safe_load((ADDON / "config.yaml").read_text())
    options = set(config.get("schema", {})) | set(config.get("options", {}))
    ports = set(config.get("ports", {}))
    problems = []
    if "ports_description" in config:
        problems.append("config.yaml: ports_description is back - port texts belong in translations/*.yaml (network)")
    files = sorted((ADDON / "translations").glob("*.yaml"))
    if not files:
        problems.append("no translations/*.yaml at all")
    for path in files:
        data = yaml.safe_load(path.read_text()) or {}
        labels = data.get("configuration", {}) or {}
        for key in sorted(options):
            entry = labels.get(key)
            if not isinstance(entry, dict):
                problems.append(f"{path.name}: option '{key}' has no entry")
                continue
            for field in ("name", "description"):
                if not str(entry.get(field) or "").strip():
                    problems.append(f"{path.name}: option '{key}' has no {field}")
        for key in sorted(set(labels) - options):
            problems.append(f"{path.name}: '{key}' describes an option config.yaml does not have")
        network = data.get("network", {}) or {}
        for port in sorted(ports):
            if not str(network.get(port) or "").strip():
                problems.append(f"{path.name}: port '{port}' has no description")
    for problem in problems:
        print(f"ERROR: {problem}")
    if not problems:
        print(f"OK: {len(options)} options and {len(ports)} ports described in {len(files)} languages")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
