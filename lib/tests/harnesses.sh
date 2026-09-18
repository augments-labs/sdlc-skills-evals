#!/usr/bin/env bash
# Offline test: every harness launcher honors the live contract. No live run.
# Each launcher is sourced in its own subshell — all four define the same
# adapter_* names, so one shell cannot hold more than one.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
hh="$here/harnesses"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }
has_fn() { # $1 file $2 function — 0 iff defined after sourcing
  ( source "$1" >/dev/null 2>&1 && command -v "$2" >/dev/null 2>&1 )
}

required="adapter_check adapter_install adapter_chain adapter_run_activation adapter_run_behavioral"

for h in "$hh"/*.sh; do
  name="$(basename "$h")"
  for fn in $required; do
    if has_fn "$h" "$fn"; then ok "$name defines $fn";
    else bad "$name defines $fn"; fi
  done
  for field in runnable runnable_reason permission_flags capabilities; do
    if grep -q "^$field=" "$h"; then ok "$name header carries $field";
    else bad "$name header carries $field"; fi
  done
  # the header must not claim flags the file never passes
  flags="$(grep '^permission_flags=' "$h" | sed 's/^permission_flags=//')"
  if [ -n "$flags" ]; then
    if grep -qF -- "$flags" "$h"; then ok "$name permission_flags matches a passed flag";
    else bad "$name permission_flags matches a passed flag ($flags)"; fi
  else
    bad "$name permission_flags is non-empty"
  fi
done

# runnable values are honest: opencode runs here, codex/kimi declare why not
grep -q '^runnable=yes' "$hh/opencode.sh" && ok "opencode runnable=yes" || bad "opencode runnable=yes"
grep -q '^runnable=no' "$hh/codex.sh" && ok "codex runnable=no" || bad "codex runnable=no"
grep -q '^runnable=no' "$hh/kimi-code.sh" && ok "kimi runnable=no" || bad "kimi runnable=no"

exit "$fails"
