#!/usr/bin/env bash
# Offline test: plugin pinning by path or ref. Builds its own throwaway
# plugin stand-in, so no sibling checkout is needed. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../pin.sh
source "$here/../pin.sh"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

standin="$(mktemp -d)"
trap 'rm -rf "$standin"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
commit="$(git -C "$standin" rev-parse HEAD)"
export SDLC_SKILLS_ROOT="$standin"

# pinning by ref prints the commit and cleans up at shell exit
run_dir="$(mktemp -d)"
got="$(lab_pin_plugin "$commit" "$run_dir")"
[ "$got" = "$commit" ] && ok "pin by ref prints the commit" || bad "pin by ref prints the commit (got $got)"
[ -z "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "captured pin leaves no worktree behind" || bad "captured pin leaves no worktree behind"
rm -rf "$run_dir"

# a same-shell pin (no capture) persists until explicit cleanup
run_dir_s="$(mktemp -d)"
lab_pin_plugin "$commit" "$run_dir_s" >"$run_dir_s/commit.txt"
[ "$(cat "$run_dir_s/commit.txt")" = "$commit" ] \
  && ok "same-shell pin prints the commit" || bad "same-shell pin prints the commit"
[ -n "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "same-shell pin persists" || bad "same-shell pin persists"
lab_pin_cleanup "$run_dir_s"
[ -z "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "pin cleanup leaves no worktree behind" || bad "pin cleanup leaves no worktree behind"
rm -rf "$run_dir_s"

# pinning by directory uses it as is and prints its commit
run_dir2="$(mktemp -d)"
got2="$(lab_pin_plugin "$standin" "$run_dir2")"
[ "$got2" = "$commit" ] && ok "pin by directory prints its commit" || bad "pin by directory prints its commit (got $got2)"
rm -rf "$run_dir2"

# an unknown ref is refused, never resolved to something else
run_dir3="$(mktemp -d)"
if lab_pin_plugin "does-not-exist-sdlc-skills-evals" "$run_dir3" >/dev/null 2>&1; then
  bad "unknown ref is refused"
else
  ok "unknown ref is refused"
fi
[ -z "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "refused pin leaves no worktree behind" || bad "refused pin leaves no worktree behind"
rm -rf "$run_dir3"

# no plugin root anywhere is refused, never a global install
run_dir4="$(mktemp -d)"
if SDLC_SKILLS_ROOT=/nonexistent/sdlc-skills-evals-root lab_pin_plugin "$commit" "$run_dir4" >/dev/null 2>&1; then
  bad "missing plugin root is refused"
else
  ok "missing plugin root is refused"
fi
rm -rf "$run_dir4"

# --- the committed upstream pin ----------------------------------------------
#
# The pin a run resolves is a COMMIT, never a mutable tag: it comes from the
# committed inventory, and a value that is not a full object name is
# refused, so no run can select new work from a tag.

lab_root="$(cd "$here/../.." && pwd)"
inv="$lab_root/config/upstream-inventory.json"

pin="$(lab_inventory_commit 2>/dev/null)"
if [ -n "$pin" ] && [ "${#pin}" -eq 40 ]; then
  ok "the committed pin is a full object name"
else
  bad "the committed pin is a full object name (got '$pin')"
fi
case "$pin" in
  *[!0-9a-f]*) bad "the committed pin is hexadecimal" ;;
  *) ok "the committed pin is hexadecimal" ;;
esac

# a version tag in place of the commit is refused
tag_inv="$standin/inventory-tag.json"
jq '.upstream.commit = "v11.0.0"' "$inv" >"$tag_inv" 2>/dev/null
if INVENTORY_PATH="$tag_inv" lab_inventory_commit >/dev/null 2>&1; then
  bad "a version tag instead of a commit is refused"
else
  ok "a version tag instead of a commit is refused"
fi

# a missing inventory is refused
if INVENTORY_PATH="$standin/no-such-inventory.json" lab_inventory_commit >/dev/null 2>&1; then
  bad "a missing inventory is refused"
else
  ok "a missing inventory is refused"
fi

# --- what a ref names --------------------------------------------------------
#
# A full object name IS a commit and is taken at face value, so a pinned
# commit needs no checkout to name. A tag is resolved to the commit it
# names. A path is its own HEAD.

face="$(SDLC_SKILLS_ROOT=/nonexistent/sdlc-skills-evals-root lab_pin_commit_of "$commit" 2>/dev/null)"
[ "$face" = "$commit" ] && ok "a commit is taken at face value" \
  || bad "a commit is taken at face value (got '$face')"

git -C "$standin" tag -f selftest-tag "$commit" >/dev/null 2>&1
tagged="$(lab_pin_commit_of selftest-tag 2>/dev/null)"
[ "$tagged" = "$commit" ] && ok "a tag resolves to the commit it names" \
  || bad "a tag resolves to the commit it names (got '$tagged')"

head_of="$(lab_pin_commit_of "$standin" 2>/dev/null)"
[ "$head_of" = "$commit" ] && ok "a path resolves to its own HEAD" \
  || bad "a path resolves to its own HEAD (got '$head_of')"

if lab_pin_commit_of does-not-exist-sdlc-skills-evals >/dev/null 2>&1; then
  bad "an unknown ref is refused"
else
  ok "an unknown ref is refused"
fi

exit "$fails"
