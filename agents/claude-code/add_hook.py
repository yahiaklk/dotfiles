"""Add the session-start hook to Claude Code settings files, once. Stdlib only; run with python3 -I.

Usage: python3 -I add_hook.py [--dry-run] <hook-command> <settings.json> ...
For each settings file that exists: if no SessionStart hook already runs <hook-command>, append one, after copying
the file to <settings.json>.bak-<timestamp>. Other keys and hooks are kept as they are. A file that doesn't exist or
doesn't parse is reported and left alone.
Exit: 0 done (including "already there"); 1 a file could not be read or written; 2 usage error.
"""

from __future__ import annotations

import json
import shutil
import sys
import time
from pathlib import Path


def has_hook(settings: dict, command: str) -> bool:
    for group in settings.get("hooks", {}).get("SessionStart", []):
        for h in group.get("hooks", []):
            if h.get("command") == command:
                return True
    return False


def add(settings: dict, command: str) -> dict:
    hooks = settings.setdefault("hooks", {})
    hooks.setdefault("SessionStart", []).append(
        {"hooks": [{"type": "command", "command": command, "timeout": 30}]}
    )
    return settings


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if len(args) < 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    command, files = args[0], [Path(a).expanduser() for a in args[1:]]
    status = 0
    for f in files:
        if not f.is_file():
            print(f"skip   {f}: no such file")
            continue
        try:
            settings = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            print(f"error  {f}: {e}", file=sys.stderr)
            status = 1
            continue
        if has_hook(settings, command):
            print(f"ok     {f}: SessionStart hook already there")
            continue
        if dry:
            print(f"would  {f}: add the SessionStart hook")
            continue
        backup = f.with_name(f"{f.name}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(f, backup)
        f.write_text(json.dumps(add(settings, command), indent=2) + "\n", encoding="utf-8")
        print(f"added  {f}: SessionStart hook (backup {backup.name})")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
