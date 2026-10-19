#!/usr/bin/env bash
# Plugin pinning by path or git ref. Sourced, never executed.
#
# lab_pin_plugin <path|ref> <run-dir> — a directory is used as is; anything
# else is resolved in $SDLC_SKILLS_ROOT and checked out as a throwaway
# worktree under the run dir. Prints the resolved commit (or the path when
# it is not a git checkout). The pin's worktree is removed at shell exit:
# inside a $(...) capture the trap is installed replacing (a chained trap
# would fire the caller's EXIT trap early in the subshell); in the calling
# shell it is chained after the caller's trap. A caller that needs the
# worktree past a capture must pin without capturing (redirect to a file
# in the current shell) or pin again. lab_pin_cleanup removes the pins
# early (same shell) or one run's worktree by path. Never falls back to a
# globally installed plugin: without a usable SDLC_SKILLS_ROOT the pin is
# refused (exit 2).

# --- the committed upstream pin ----------------------------------------------
#
# The pin a run resolves is a COMMIT, never a mutable tag: it is the
# upstream.commit of the committed inventory (config/upstream-inventory.json),
# which the static gate checks offline. A value that is not a full object
# name is refused, so no run can select new work from a tag. INVENTORY_PATH
# is the seam bin/check reads too, so one artifact has one path.

_lab_is_commit() { # $1 — 0 when it is a full object name
  case "${1:-}" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ]
}

_lab_inventory_path() { # prints the inventory's path
  local root inv
  if [ -n "${SDLC_SKILLS_EVALS_ROOT:-}" ]; then
    root="$SDLC_SKILLS_EVALS_ROOT"
  else
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  inv="${INVENTORY_PATH:-$root/config/upstream-inventory.json}"
  case "$inv" in /*) : ;; *) inv="$root/$inv" ;; esac
  printf '%s\n' "$inv"
}

lab_inventory_commit() { # prints the committed upstream pin; 2 when there is none
  local inv commit
  inv="$(_lab_inventory_path)"
  [ -f "$inv" ] || { printf 'no upstream inventory at %s\n' "$inv" >&2; return 2; }
  command -v jq >/dev/null 2>&1 || { printf 'needs `jq`\n' >&2; return 2; }
  commit="$(jq -r '.upstream.commit // empty' "$inv" 2>/dev/null)" \
    || { printf 'cannot read the upstream pin from %s\n' "$inv" >&2; return 2; }
  if ! _lab_is_commit "$commit"; then
    printf 'the upstream pin is not a commit: %s\n' "${commit:-none}" >&2
    return 2
  fi
  printf '%s\n' "$commit"
}

# lab_pin_commit_of <path|ref> — the commit a plugin reference names, with
# no worktree and no checkout of its own: a path is its own HEAD, a full
# object name is a commit and is taken at face value, and any other ref
# (a tag, a branch) is resolved against the plugin checkout. A tag may be
# NAMED here; the commit it names is what a run then uses.
lab_pin_commit_of() {
  [ "$#" -eq 1 ] || return 127
  local src="$1" root commit
  if [ -d "$src" ]; then
    commit="$(git -C "$src" rev-parse HEAD 2>/dev/null)" \
      || { printf 'not a plugin checkout: %s\n' "$src" >&2; return 2; }
    printf '%s\n' "$commit"
    return 0
  fi
  if _lab_is_commit "$src"; then
    printf '%s\n' "$src"
    return 0
  fi
  root="${SDLC_SKILLS_ROOT:-}"
  if [ -z "$root" ]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/../sdlc-skills"
  fi
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 \
    || { printf 'not a plugin checkout: %s\n' "$root" >&2; return 2; }
  commit="$(git -C "$root" rev-parse --verify --quiet "$src^{commit}" 2>/dev/null)" \
    || { printf 'cannot resolve %s in %s\n' "$src" "$root" >&2; return 2; }
  printf '%s\n' "$commit"
}

_lab_pin_worktrees=""

_lab_pin_remove() { # $1 worktree path — removes via the owning repo, from any CWD
  local wt="$1" gitfile owner
  [ -n "$wt" ] && [ -f "$wt/.git" ] || return 0
  gitfile="$(cat "$wt/.git" 2>/dev/null)" || return 0
  case "$gitfile" in
    "gitdir: "*) owner="${gitfile#gitdir: }"; owner="${owner%%/worktrees/*}" ;;
    *) return 0 ;;
  esac
  [ -n "$owner" ] && git --git-dir="$owner" worktree remove --force "$wt" >/dev/null 2>&1
}

lab_pin_cleanup() {
  # $* run-dirs (each one's plugin/ worktree is removed) plus any worktree
  # pinned in this shell. Run-dirs are named explicitly because a pin
  # captured via $(...) records nothing in the caller's shell — the
  # worktree always lives at <run-dir>/plugin, so no ledger is needed.
  local wt d
  for wt in $_lab_pin_worktrees; do
    _lab_pin_remove "$wt"
  done
  for d in "$@"; do
    [ -n "$d" ] && _lab_pin_remove "$d/plugin"
  done
  _lab_pin_worktrees=""
}

_lab_pin_chain() {
  # Chain lab_pin_cleanup after the current shell's EXIT trap, if any.
  local existing
  existing="$(trap -p EXIT | sed "s/^trap -- '//; s/' EXIT\$//")"
  if [ -n "$existing" ]; then
    # shellcheck disable=SC2064
    trap "$existing; lab_pin_cleanup" EXIT
  else
    trap lab_pin_cleanup EXIT
  fi
}

lab_pin_plugin() { # $1 path|ref  $2 run-dir
  [ "$#" -eq 2 ] || return 127
  local src="$1" run_dir="$2" root commit wt
  if [ -d "$src" ]; then
    if commit="$(git -C "$src" rev-parse HEAD 2>/dev/null)"; then
      printf '%s\n' "$commit"
    else
      printf '%s\n' "$src"
    fi
    return 0
  fi
  root="${SDLC_SKILLS_ROOT:-}"
  if [ -z "$root" ]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/../sdlc-skills"
  fi
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 2
  git -C "$root" rev-parse --verify --quiet "$src^{commit}" >/dev/null 2>&1 || return 2
  commit="$(git -C "$root" rev-parse "$src^{commit}")" || return 2
  wt="$run_dir/plugin"
  git -C "$root" worktree add --detach "$wt" "$commit" >/dev/null 2>&1 || return 2
  _lab_pin_worktrees="$_lab_pin_worktrees $wt"
  if [ "${BASH_SUBSHELL:-0}" -gt 0 ]; then trap lab_pin_cleanup EXIT
  else _lab_pin_chain; fi
  printf '%s\n' "$commit"
}
