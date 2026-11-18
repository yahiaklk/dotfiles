"""Add the anzar brief file to OpenCode's "instructions", once. Stdlib only; run with python3 -I.

Usage: python3 -I add_instructions.py [--dry-run] <brief-path> <opencode.json>
The entry is the brief path as given (e.g. "~/.cache/anzar/brief.md"; OpenCode resolves "~/" from home). The file is
copied to <opencode.json>.bak-<timestamp> first. Other keys are kept. An opencode.jsonc (comments) is not edited:
the entry to add is printed instead.
Exit: 0 done (including "already there"); 1 the file could not be read or written; 2 usage error.
"""

from __future__ import annotations

import json
import shutil
import sys
import time
from pathlib import Path


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if len(args) != 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    entry, f = args[0], Path(args[1]).expanduser()
    if f.suffix == ".jsonc" or not f.exists() and f.with_suffix(".jsonc").exists():
        print(f'manual {f}: add "{entry}" to "instructions" by hand (JSONC is not edited)')
        return 0
    try:
        config = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {"$schema": "https://opencode.ai/config.json"}
    except (OSError, json.JSONDecodeError) as e:
        print(f"error  {f}: {e}", file=sys.stderr)
        return 1
    instructions = config.get("instructions", [])
    if entry in instructions:
        print(f"ok     {f}: instructions already list {entry}")
        return 0
    if dry:
        print(f"would  {f}: add {entry} to instructions")
        return 0
    if f.exists():
        shutil.copy2(f, f.with_name(f"{f.name}.bak-{time.strftime('%Y%m%d-%H%M%S')}"))
    else:
        f.parent.mkdir(parents=True, exist_ok=True)
    config["instructions"] = [*instructions, entry]
    f.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print(f"added  {f}: {entry} in instructions")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
