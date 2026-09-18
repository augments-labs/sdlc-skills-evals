#!/usr/bin/env bash
# Offline test: bin/grade on a recorded fixture run directory. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$here/lib/tests/fixtures/grade-run" "$work/run"
"$here/bin/grade" "$work/run" >/dev/null 2>&1 || { bad "grade exits 0 on mixed run"; exit "$fails"; }
g="$work/run/grading.json"
[ -f "$g" ] || { bad "grading.json written"; exit "$fails"; }
jq -e '.summary.passed == 3 and .summary.failed == 2 and .summary.needs_review == 1
  and .summary.total == 6 and .summary.pass_rate == 0.5' "$g" >/dev/null \
  && ok "summary counts the mixed run" || bad "summary counts the mixed run"
jq -e 'all(.assertion_results[]; has("text") and has("evidence")
  and (.passed == true or .passed == false or . == {text:.text, passed:"needs_review", evidence:.evidence}))' "$g" >/dev/null \
  && ok "every result carries text and evidence" || bad "every result carries text and evidence"
jq -e '[.assertion_results[] | select(.passed == "needs_review")] | length == 1' "$g" >/dev/null \
  && ok "untagged assertion needs review" || bad "untagged assertion needs review"
jq -e '[.assertion_results[] | select(.passed == true)] | length == 3' "$g" >/dev/null \
  && ok "three mechanical passes" || bad "three mechanical passes"
jq -e '[.assertion_results[] | select(.passed == true and (.evidence | length > 0))] | length == 3' "$g" >/dev/null \
  && ok "passes cite concrete evidence" || bad "passes cite concrete evidence"
jq -e '.assertion_results[1].passed == false and (.assertion_results[1].evidence | length > 0)' "$g" >/dev/null \
  && ok "failures cite actuals, not silence" || bad "failures cite actuals, not silence"

exit "$fails"
