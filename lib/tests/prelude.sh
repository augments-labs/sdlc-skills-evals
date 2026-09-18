#!/usr/bin/env bash
# Offline test: prelude 127 band, `not`, and the check counter. No live run.
#
# Arity probes run in subshells: the pre-fix library answers wrong arity by
# tripping `set -u` and aborting the caller, so an unguarded probe would kill
# this test instead of failing it.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../prelude.sh
source "$here/../prelude.sh"

fails=0
expect_eq() { # $1 actual $2 expected $3 description
  if [ "$1" = "$2" ]; then printf '  ok    %s\n' "$3";
  else printf '  FAIL  %s (got %s, want %s)\n' "$3" "$1" "$2"; fails=1; fi
}
probe() { # $1 expected $2 description $3... command words; runs in a subshell
  local want="$1" desc="$2"; shift 2
  ( "$@" >/dev/null 2>&1 ); local got="$?"
  expect_eq "$got" "$want" "$desc"
}

# wrong arity is broken (127), not failed (1) and never a caller abort
probe 127 "assert_file with no args is 127" assert_file
probe 127 "assert_contains with one arg is 127" assert_contains "only-one"
probe 127 "assert_not_contains with two args is 127" assert_not_contains "a" "b"
probe 127 "pass with no args is 127" pass
probe 127 "fail with no args is 127" fail
probe 127 "note with no args is 127" note
probe 127 "added_since_baseline with no args is 127" added_since_baseline

# a check that ran and did not hold is failed (1), not broken
probe 1 "absent artifact is 1" assert_file /nonexistent/sdlc-skills-evals-absent "absent artifact"
probe 1 "missing match is 1" assert_contains "hello" "zzz" "missing match"

# `not` inverts 0/1 and refuses to invert 127
probe 0 "not inverts 1 to 0" not assert_contains "hello" "zzz" "negated miss"
probe 1 "not inverts 0 to 1" not assert_contains "hello" "ell" "negated hit"
probe 127 "not on a 127 stays 127" not assert_file

# `not` itself exists as a function (not a coincidental command-not-found)
expect_eq "$(command -v not)" "not" "not is a defined function"

# counter: real checks increment it; reporting does not
_lab_checks_run=0
assert_contains "hello" "ell" "counter hit" >/dev/null 2>&1
expect_eq "$_lab_checks_run" 1 "one assert_* increments the counter once"
assert_result >/dev/null 2>&1
expect_eq "$_lab_checks_run" 1 "assert_result does not increment the counter"

exit "$fails"
