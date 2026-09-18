#!/usr/bin/env bash
# Shared logging, tool requirements, and root resolution. Sourced, never executed.

log() { printf '%s\n' "$*" >&2; }

die() { log "error: $*"; return 1; }

require_tool() { # $* tool names — 0 when all present, 127 naming the first missing one
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || { log "needs \`$t\`"; return 127; }
  done
  return 0
}

lab_run_dir() { # $1 prefix — creates a run dir under TMPDIR and prints it
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/${1:-run}.XXXXXX")" || return 127
  printf '%s\n' "$d"
}

lab_root() {
  # SDLC_SKILLS_EVALS_ROOT wins so every bin/* command works from any
  # working directory; otherwise the directory above lib/ (this file's
  # parent), which keeps worktree-nested checkouts working — the default
  # is resolved from the lab root, never from the caller's CWD.
  if [ -n "${SDLC_SKILLS_EVALS_ROOT:-}" ]; then printf '%s\n' "$SDLC_SKILLS_EVALS_ROOT"; return 0; fi
  ( cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P )
}

plugin_root() {
  # SDLC_SKILLS_ROOT wins; otherwise ../sdlc-skills relative to the lab
  # root (not the CWD). Refused when it is not a git checkout — a globally
  # installed plugin never satisfies a run.
  local root="${SDLC_SKILLS_ROOT:-$(lab_root)/../sdlc-skills}"
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { log "not a plugin checkout: $root"; return 2; }
  printf '%s\n' "$root"
}
