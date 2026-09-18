#!/usr/bin/env bash
# Assertion helpers for behavioural scenarios. Sourced, never executed.
#
# A scenario's assertions decide the verdict, and the verdict is this script's
# EXIT CODE — not prose in a summary written by the agent that wants it green.
# Call `assert_*` freely; call `assert_result` last to return the verdict.
#
# Exit bands: 0 a check ran and held · 1 a check ran and did not hold ·
# 127 the check itself is broken (wrong arity, missing tooling). `not`
# refuses to invert 127, so a broken check can never become a pass.
# The guards below exist because the old code answered wrong arity by
# tripping `set -u` in the caller and aborting the runner mid-scenario.
#
# `_lab_checks_run` counts invocations of the three `assert_*` predicates
# only — markers (`pass`, `fail`, `note`), the `added_since_baseline`
# helper, and `assert_result` do not count. The runner reads it to detect
# "no check ran": a scenario that only notes and reports must not be green.

_af=0
_lab_checks_run=0

_broken() { printf '  BROKEN %s\n' "$1" >&2; return 127; }

pass() { [ "$#" -eq 1 ] || { _broken "pass needs 1 argument (description)"; return 127; }; printf '  ok    %s\n' "$1" >&2; }
fail() { [ "$#" -eq 1 ] || { _broken "fail needs 1 argument (description)"; return 127; }; printf '  FAIL  %s\n' "$1" >&2; _af=1; }
note() { [ "$#" -eq 1 ] || { _broken "note needs 1 argument (description)"; return 127; }; printf '  ---   %s\n' "$1" >&2; }

assert_file() { # $1 path (glob ok)  $2 description
  [ "$#" -eq 2 ] || { _broken "assert_file needs 2 arguments (path, description)"; return 127; }
  _lab_checks_run=$((_lab_checks_run + 1))
  local f; f="$(compgen -G "$1" 2>/dev/null | head -1)"
  [ -n "$f" ] && { pass "$2 ($f)"; ASSERT_MATCH="$f"; return 0; }
  fail "$2 — nothing matched $1"; ASSERT_MATCH=""; return 1
}

assert_contains() { # $1 haystack  $2 regex  $3 description
  [ "$#" -eq 3 ] || { _broken "assert_contains needs 3 arguments (haystack, regex, description)"; return 127; }
  command -v grep >/dev/null 2>&1 || { _broken "assert_contains needs grep"; return 127; }
  _lab_checks_run=$((_lab_checks_run + 1))
  printf '%s' "$1" | grep -qiE -- "$2" && { pass "$3"; return 0; }
  fail "$3 — expected to match: $2"; return 1
}

assert_not_contains() { # $1 haystack  $2 regex  $3 description
  [ "$#" -eq 3 ] || { _broken "assert_not_contains needs 3 arguments (haystack, regex, description)"; return 127; }
  command -v grep >/dev/null 2>&1 || { _broken "assert_not_contains needs grep"; return 127; }
  _lab_checks_run=$((_lab_checks_run + 1))
  printf '%s' "$1" | grep -qiE -- "$2" && { fail "$3 — matched: $2"; return 1; }
  pass "$3"; return 0
}

# Everything added since the runner's baseline commit, COMMITTED or not.
# Untracked-only detection is a false-negative trap: an agent that wraps its
# branch commits its work, `git status` then reports a clean tree, and a real
# pass gets scored as "produced nothing". That happened once, on Kimi.
added_since_baseline() { # $1 workdir
  [ "$#" -eq 1 ] || { _broken "added_since_baseline needs 1 argument (workdir)"; return 127; }
  command -v git >/dev/null 2>&1 || { _broken "added_since_baseline needs git"; return 127; }
  ( cd "$1" || return
    local root; root="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
    { [ -n "$root" ] && git diff --name-only --diff-filter=A "$root" HEAD 2>/dev/null
      git status --porcelain -uall 2>/dev/null | awk '$1=="??"{print $2}'; } | sort -u )
}

# `not` negates a check outcome (0↔1) and refuses to invert a broken check:
# `not` on a 127 stays 127.
not() {
  [ "$#" -ge 1 ] || { _broken "not needs a command to negate"; return 127; }
  "$@"; local rc="$?"
  [ "$rc" -eq 127 ] && return 127
  [ "$rc" -eq 0 ] && return 1
  return 0
}

assert_result() { [ "$_af" -eq 0 ] && { echo "  RESULT: pass" >&2; return 0; }; echo "  RESULT: fail" >&2; return 1; }
