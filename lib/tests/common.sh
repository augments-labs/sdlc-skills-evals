#!/usr/bin/env bash
# Offline test: shared logging, tool requirements, roots. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../common.sh
source "$here/../common.sh"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

# require_tool passes for present tools, 127 for absent ones
require_tool bash jq git >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "present tools pass" || bad "present tools pass"
require_tool definitely-not-a-real-tool-sdlc-skills-evals >/dev/null 2>&1
[ "$?" -eq 127 ] && ok "absent tool is 127" || bad "absent tool is 127"

# log goes to stderr, die exits non-zero with the message on stderr
[ -z "$(log hello 2>/dev/null)" ] && [ -n "$(log hello 2>&1 >/dev/null)" ] \
  && ok "log writes to stderr" || bad "log writes to stderr"
( die "boom" >/dev/null 2>err.txt ); rc="$?"
[ "$rc" -ne 0 ] && grep -q "boom" err.txt && ok "die exits non-zero with the message" || bad "die exits non-zero with the message"
rm -f err.txt

# run dirs live under TMPDIR and exist
d="$(lab_run_dir test-prefix)"
case "$d" in "${TMPDIR:-/tmp}"/*) ok "run dir lives under TMPDIR";; *) bad "run dir lives under TMPDIR (got $d)";; esac
[ -d "$d" ] && ok "run dir exists" || bad "run dir exists"
rm -rf "$d"

# lab_root is the directory above lib/
[ "$(lab_root)" = "$(cd "$here/../.." && pwd -P)" ] \
  && ok "lab_root is the repo root" || bad "lab_root is the repo root (got $(lab_root))"
# ... and the override wins (read indirectly by lab_root in lib/common.sh).
# shellcheck disable=SC2034
SDLC_SKILLS_EVALS_ROOT=/tmp/lab-root-override-sdlc-skills-evals
[ "$(lab_root)" = "/tmp/lab-root-override-sdlc-skills-evals" ] \
  && ok "SDLC_SKILLS_EVALS_ROOT overrides lab_root" || bad "SDLC_SKILLS_EVALS_ROOT overrides lab_root"
unset SDLC_SKILLS_EVALS_ROOT

# plugin_root refuses a non-checkout, never guesses
if SDLC_SKILLS_ROOT=/nonexistent/sdlc-skills-evals-root plugin_root >/dev/null 2>&1; then
  bad "plugin_root refuses a non-checkout"
else
  ok "plugin_root refuses a non-checkout"
fi
# ... and a real checkout passes (throwaway stand-in, no sibling needed)
standin="$(mktemp -d)"
git -C "$standin" init -q
SDLC_SKILLS_ROOT="$standin" plugin_root >/dev/null 2>&1 \
  && ok "plugin_root accepts a checkout" || bad "plugin_root accepts a checkout"
rm -rf "$standin"

exit "$fails"
