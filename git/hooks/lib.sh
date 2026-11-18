# Shared checks for the git hooks in this directory. POSIX sh, no dependencies.
#
# Rules (engineering-playbook, P2 DevOps, owner decision 2026-11-18):
#   Commits:  Conventional Commits 1.0.0 header, lowercase type from TYPES,
#             optional (scope), optional "!", ": ", a description.
#             Subject at most 72 characters, no trailing period, blank line
#             before any body. No AI attribution trailers.
#             Exempt: git's own "Merge ..." and "Revert ..." subjects, and
#             fixup!/squash!/amend! commits (they are squashed away).
#   Branches: main | develop | <type>/<kebab> (at most 50 characters) | archive/<anything>
#             | worktree-agent-<id> (agent scratch branches: local only, never pushed).
#
# Scope: these hooks run only for repositories under ~/projects/ (see
# projects.gitconfig and the includeIf in .gitconfig).
# Opt-out for repositories that follow someone else's conventions (third-party
# clones): `git config hooks.conventions false` in that repository. The checks
# are skipped; the repository's own hooks still run.

conventions_on() {
  [ "$(git config --bool hooks.conventions 2>/dev/null)" != false ]
}

TYPES='feat|fix|docs|test|refactor|perf|build|ci|chore|revert|style'
BRANCH_MAX=50
SUBJECT_MAX=72

hook_fail() {
  printf 'git hook: %s\n' "$1" >&2
  shift
  for line in "$@"; do printf '  %s\n' "$line" >&2; done
  return 1
}

# check_branch <name> <local|push>
check_branch() {
  name=$1 mode=$2
  [ -z "$name" ] && return 0            # detached HEAD (rebase, bisect)
  case $name in
    main|develop|archive/?*) return 0 ;;
    worktree-agent-*)
      if [ "$mode" = push ]; then
        hook_fail "branch '$name' is an agent scratch branch and stays local." \
          "Merge it, or rename it to <type>/<kebab> before pushing."
        return 1
      fi
      return 0 ;;
  esac
  if ! printf '%s\n' "$name" | grep -Eq "^($TYPES)/[a-z0-9]+(-[a-z0-9]+)*\$"; then
    hook_fail "branch name '$name' does not follow <type>/<kebab-description>." \
      "type: one of ${TYPES}" \
      "example: ci/quality-workflow, fix/fts-on-fresh-runner" \
      "rename: git branch -m <new-name>"
    return 1
  fi
  if [ "${#name}" -gt "$BRANCH_MAX" ]; then
    hook_fail "branch name '$name' is ${#name} characters; the limit is $BRANCH_MAX."
    return 1
  fi
  return 0
}

# check_message_file <file>: the commit message as git would record it.
check_message_file() {
  # Drop comment lines and leading blank lines, as git's default cleanup does.
  msg=$(grep -v '^#' "$1" | sed '/./,$!d')
  subject=$(printf '%s\n' "$msg" | sed -n 1p)
  second=$(printf '%s\n' "$msg" | sed -n 2p)

  if printf '%s\n' "$msg" | grep -Eiq \
      '^(co-authored-by:.*(claude|anthropic|copilot|openai|chatgpt|gemini|cursor|codex)|claude-session:)|generated (with|by) .*claude'; then
    hook_fail "commit message carries an AI attribution trailer; these are not allowed." \
      "Remove the Co-Authored-By / Claude-Session / 'Generated with' line."
    return 1
  fi

  case $subject in
    "Merge "*|"Revert \""*|"fixup! "*|"squash! "*|"amend! "*) return 0 ;;
  esac

  if ! printf '%s\n' "$subject" | grep -Eq "^($TYPES)(\([a-z0-9][a-z0-9._/-]*\))?!?: [^ ]"; then
    hook_fail "subject does not follow Conventional Commits: '$subject'" \
      "format: <type>(<optional scope>)!: <description>" \
      "type: one of ${TYPES}" \
      "example: fix(search): install fts before BM25 queries"
    return 1
  fi
  if [ "${#subject}" -gt "$SUBJECT_MAX" ]; then
    hook_fail "subject is ${#subject} characters; the limit is $SUBJECT_MAX." "'$subject'"
    return 1
  fi
  case $subject in
    *.) hook_fail "subject ends with a period: '$subject'"; return 1 ;;
  esac
  if [ -n "$second" ]; then
    hook_fail "leave a blank line between the subject and the body."
    return 1
  fi
  return 0
}

# chain <hook-name> [args...]: run the repository's own hook of that name, if any
# (for example one installed by pre-commit). core.hooksPath otherwise hides it.
chain() {
  hook=$(git rev-parse --git-common-dir)/hooks/$1
  shift
  if [ -x "$hook" ]; then
    "$hook" "$@"
    return $?
  fi
  return 0
}
