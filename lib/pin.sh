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

# lab_pin_tree <path|ref> — the TREE a run installs for a plugin
# reference. A directory is the operator's own working tree and is used as
# it is, so the tree is the path; anything else is pinned into a
# throwaway worktree, so the tree is the commit it names. A runner that
# names one of these names what it will install.
lab_pin_tree() {
  [ "$#" -eq 1 ] || return 127
  local src="$1" commit
  if [ -d "$src" ]; then
    printf '%s\n' "$src"
    return 0
  fi
  commit="$(lab_pin_commit_of "$src" 2>/dev/null)" || return 2
  printf '%s\n' "$commit"
}

# lab_pin_note <flag> <path|ref> — the note a runner prints beside the
# tree a reference names: where the tree came from, and for a directory,
# where that tree is (a working tree is not a commit, and calling it one
# would describe content the run never measured).
lab_pin_note() {
  [ "$#" -eq 2 ] || return 127
  local flag="$1" src="$2" commit
  if [ -d "$src" ]; then
    commit="$(lab_pin_commit_of "$src" 2>/dev/null)" || commit=""
    if [ -n "$commit" ]; then
      printf -- '%s %s; working tree at %s' "$flag" "$src" "$commit"
    else
      printf -- '%s %s' "$flag" "$src"
    fi
    return 0
  fi
  commit="$(lab_pin_commit_of "$src" 2>/dev/null)" || commit=""
  if [ -n "$commit" ]; then
    printf -- '%s %s' "$flag" "$src"
  else
    printf -- '%s %s; a run resolves it against the plugin checkout' "$flag" "$src"
  fi
}

# --- which skill text a reference names --------------------------------------
#
# lab_pin_identity <path|ref> <skill> — prints {"commit": ..., "skill_tree":
# ...} for the tree a run installs: the full commit it comes from, and the
# git tree hash of the skill's directory at that commit
# (git rev-parse <commit>:skills/<phase>/<name>). The tree hash names the
# skill text by content, so it still matches after a squash merge changes
# the commit.
#
# A ref is resolved in the plugin checkout, and a run installs it with `git
# archive`: the hash names what the run installed only while the archive
# equals the tree. An export-ignore or export-subst rule in .gitattributes
# makes it differ, and so does any conversion git applies on checkout (below):
# git archive applies the same ones. At the pinned commit the plugin has no
# export-ignore or export-subst rule, and its other rules (eol=lf, binary)
# convert nothing; re-check its .gitattributes when the pin moves.
#
# A directory is identified only when it is the top of a git work tree whose
# skill directory is exactly HEAD's: `git -c core.fileMode=true status
# --porcelain --untracked-files=all --ignored -- <skill dir>` prints nothing,
# and no file in it is marked assume-unchanged or skip-worktree. Then it is
# HEAD and that tree. Any other directory is {null, null} — a run installs the
# directory as it stands, and naming a commit for text that differs from it
# would describe content the run never measured. That includes a directory
# whose HEAD holds no single directory for the skill; a reference whose
# commit holds none keeps its commit and has a null skill_tree, and a
# reference the plugin checkout has no commit for is {null, null}.
#
# The check is git's, so it compares through git's own conversions. Where git
# converts a file on checkout (core.autocrlf=true, or an eol=crlf, filter or
# ident attribute, for example), a directory git calls clean can differ in
# bytes from the tree, and is still identified; so is one that holds a
# symlink as a plain file (core.symlinks=false). A commit is no way round the
# conversions, which git archive applies too: the name is exact only where
# git converts nothing in the skill directory.
#
# The reason for a null goes to stderr. Returns 0 for any identity, a null
# one included (127 only on a wrong argument count): an unnamed tree is a
# fact to record, not an error.

_lab_skill_dir_at() { # $1 repo $2 commit $3 skill — prints the skill's directory in that commit
  local hits
  hits="$(git -C "$1" ls-tree -r --name-only "$2" -- skills 2>/dev/null \
    | awk -F/ -v s="$3" '$NF == "SKILL.md" && ((NF == 3 && $2 == s) || (NF == 4 && $3 == s))')"
  [ -n "$hits" ] && [ "$(printf '%s\n' "$hits" | wc -l)" -eq 1 ] || return 1
  printf '%s\n' "${hits%/SKILL.md}"
}

_lab_identity_json() { # $1 commit ("" = null) $2 skill tree ("" = null)
  local c=null t=null
  [ -z "$1" ] || c="\"$1\""
  [ -z "$2" ] || t="\"$2\""
  printf '{"commit": %s, "skill_tree": %s}\n' "$c" "$t"
}

lab_pin_identity() {
  [ "$#" -eq 2 ] || return 127
  local src="$1" skill="$2" root commit dir tree dirty err unseen
  if [ -d "$src" ]; then
    if ! err="$(git -C "$src" rev-parse --show-toplevel 2>&1 >/dev/null)"; then
      printf 'no identity for %s: git cannot read it as a work tree (%s)\n' "$src" "$(head -n 1 <<<"$err")" >&2
      _lab_identity_json "" ""; return 0
    fi
    if [ -n "$(git -C "$src" rev-parse --show-prefix 2>/dev/null)" ]; then
      printf 'no identity for %s: not the top of a git work tree\n' "$src" >&2
      _lab_identity_json "" ""; return 0
    fi
    if ! commit="$(git -C "$src" rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null)"; then
      printf 'no identity for %s: the work tree has no commit\n' "$src" >&2
      _lab_identity_json "" ""; return 0
    fi
    if ! dir="$(_lab_skill_dir_at "$src" "$commit" "$skill")"; then
      printf 'no identity for %s: HEAD holds no single skills/[<phase>/]%s/SKILL.md\n' "$src" "$skill" >&2
      _lab_identity_json "" ""; return 0
    fi
    # A run installs the directory as it stands, so the check sees what plain
    # `git status` leaves out: untracked files whatever
    # status.showUntrackedFiles says, ignored ones, and a file mode HEAD does
    # not hold where core.fileMode is off — the tree hash covers modes.
    if ! dirty="$(git -C "$src" -c core.fileMode=true status --porcelain --untracked-files=all --ignored -- "$dir" 2>&1)"; then
      printf 'no identity for %s: git status failed on %s (%s)\n' "$src" "$dir" "$(head -n 1 <<<"$dirty")" >&2
      _lab_identity_json "" ""; return 0
    fi
    if [ -n "$dirty" ]; then
      printf "no identity for %s: %s has uncommitted, untracked or ignored files, so its text is no commit's\n" "$src" "$dir" >&2
      _lab_identity_json "" ""; return 0
    fi
    # git status does not look at a file marked assume-unchanged or
    # skip-worktree (any `git ls-files -v` tag but H), so it cannot say that
    # file is HEAD's.
    if ! unseen="$(git -C "$src" ls-files -v -- "$dir" 2>&1)"; then
      printf 'no identity for %s: git ls-files failed on %s (%s)\n' "$src" "$dir" "$(head -n 1 <<<"$unseen")" >&2
      _lab_identity_json "" ""; return 0
    fi
    if grep -qv '^H ' <<<"$unseen"; then
      printf 'no identity for %s: %s holds a file git status does not check (assume-unchanged or skip-worktree)\n' "$src" "$dir" >&2
      _lab_identity_json "" ""; return 0
    fi
    root="$src"
  else
    root="${SDLC_SKILLS_ROOT:-}"
    if [ -z "$root" ]; then
      root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/../sdlc-skills"
    fi
    if ! commit="$(git -C "$root" rev-parse --verify --quiet "$src^{commit}" 2>/dev/null)"; then
      printf 'no identity for %s: the plugin checkout %s has no such commit\n' "$src" "$root" >&2
      _lab_identity_json "" ""; return 0
    fi
    if ! dir="$(_lab_skill_dir_at "$root" "$commit" "$skill")"; then
      printf 'no skill tree for %s: %s holds no single skills/[<phase>/]%s/SKILL.md\n' "$skill" "$commit" "$skill" >&2
      _lab_identity_json "$commit" ""; return 0
    fi
  fi
  if ! tree="$(git -C "$root" rev-parse --verify --quiet "$commit:$dir" 2>/dev/null)"; then
    printf 'no skill tree for %s: cannot read %s:%s\n' "$skill" "$commit" "$dir" >&2
    if [ -d "$src" ]; then _lab_identity_json "" ""; else _lab_identity_json "$commit" ""; fi
    return 0
  fi
  _lab_identity_json "$commit" "$tree"
}

# --- which description a tree carries -----------------------------------------
#
# lab_description_sha256 <SKILL.md> — prints the SHA-256 of the exact bytes
# of the frontmatter line that begins `description:` in the skill's
# SKILL.md, without its newline. The newline is the one LF byte that ends
# the line; every other byte of the line is hashed as it is, a trailing
# space or CR included. The frontmatter is the block a first line of exactly
# `---` opens and the next line of exactly `---`, or the end of the file,
# closes; the first line in it that begins `description:` is the one
# hashed. A file with CRLF line endings therefore has no hash: its first
# line is `---` and a CR, so it opens no frontmatter. Only that first line
# is tested so: where it ends in LF alone, a CR that ends the description
# line is hashed with it. The same value, by hand:
#
#   LC_ALL=C awk 'NR == 1 { if ($0 != "---") exit; next }
#                 $0 == "---" { exit }
#                 /^description:/ { printf "%s", $0; exit }' SKILL.md | sha256sum
#
# Prints nothing and returns 1 when the file has no such line.

lab_description_sha256() {
  [ "$#" -eq 1 ] || return 127
  local line
  [ -r "$1" ] || return 1
  line="$(LC_ALL=C awk 'NR == 1 { if ($0 != "---") exit; next }
                        $0 == "---" { exit }
                        /^description:/ { print; exit }' "$1")" || return 1
  [ -n "$line" ] || return 1
  printf '%s' "$line" | sha256sum | cut -d' ' -f1
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
