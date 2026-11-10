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

# The paths changed in a git work tree since a base commit, one per line,
# sorted: added (tracked or not, ignored files aside), modified, deleted,
# and a rename git detected by its destination. Committed and uncommitted
# changes both count. Paths are read NUL-separated, so a space or a quote
# stays part of its path. Returns non-zero, its output then incomplete, when
# git cannot compute the list (no repository, or a base it does not hold).
lab_changed_files() { # $1 work tree $2 base commit
  ( set -o pipefail
    cd "$1" && { git diff --name-only -z -M "$2" -- && git ls-files -o --exclude-standard -z; } \
      | tr '\0' '\n' | LC_ALL=C sort -u )
}

# The runs of one arm directory, one per line as "<run number> <dir>", in
# number order: the arm itself as run 1, or its run-<k>/ directories when
# bin/evaluate repeated the arm (--runs N above 1). A directory with no
# run- entry comes back as run 1 whatever it holds. Return 2, the reason on
# stderr and nothing on stdout, for a name that begins run- and is not
# run-<k> (k digits, counted from 1, no leading zero), for a run-<k> that is
# not a directory (a symlink to one counts as one), and for run-<k>/ beside
# one of a run's own files: eval-case.json, outputs, run_status.json,
# grading.json, timing.json. The numbers are text here, never shell
# arithmetic.
lab_arm_runs() { # $1 arm dir
  local arm="${1%/}" r k f out=""
  for r in "$arm"/run-*; do
    [ -e "$r" ] || [ -L "$r" ] || continue
    k="${r##*/run-}"
    case "$k" in
      ''|0*|*[!0-9]*) log "not a run directory: $r (bin/evaluate writes run-<k>/, k from 1)"; return 2;;
    esac
    [ -d "$r" ] || { log "not a run directory: $r is not a directory"; return 2; }
    out="$out$k $r"$'\n'
  done
  [ -n "$out" ] || { printf '1 %s\n' "$arm"; return 0; }
  for f in eval-case.json outputs run_status.json grading.json timing.json; do
    [ ! -e "$arm/$f" ] || {
      log "$arm holds $f beside run-<k>/ directories: an arm is one run or run-<k>/, not both"; return 2; }
  done
  printf '%s' "$out" | sort -n
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
