#!/bin/sh
# Claude Code SessionStart hook: puts the repo's project toolkit (anzar-brief) into the session's context.
# Claude Code passes JSON on stdin (it carries "cwd"); whatever this prints on stdout, with exit 0, becomes context.
# It must never block or break a session: no anzar, no uv, an error or a slow run all end quietly with exit 0.
# ANZAR_DIR overrides where anzar is checked out (default ~/projects/anzar).
# ANZAR_BRIEF=off turns it off for one session (e.g. `ANZAR_BRIEF=off claude`), for with/without comparisons.
[ "${ANZAR_BRIEF:-on}" = off ] && exit 0
ANZAR_DIR=${ANZAR_DIR:-$HOME/projects/anzar}
[ -d "$ANZAR_DIR" ] || exit 0
command -v uv >/dev/null 2>&1 || exit 0
cwd=$(python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("cwd") or "")' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
# --no-sync: never sync the venv the live anzar server runs from.
timeout 20 uv run --no-sync --quiet --directory "$ANZAR_DIR" anzar-brief --cwd "$cwd" </dev/null 2>/dev/null
exit 0
