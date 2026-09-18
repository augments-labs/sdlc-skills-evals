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

exit "$fails"
