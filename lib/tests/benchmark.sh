#!/usr/bin/env bash
# Offline test: bin/benchmark over a fixture iteration. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -r "$here/lib/tests/fixtures/bench-iter" "$work/iter"
"$here/bin/benchmark" "$work/iter" >/dev/null 2>&1 || { bad "benchmark exits 0"; exit "$fails"; }
b="$work/iter/benchmark.json"
[ -f "$b" ] || { bad "benchmark.json written"; exit "$fails"; }
jq -e '.run_summary.with_skill.pass_rate == {mean:0.75, stddev:0.25}
  and .run_summary.with_skill.time_seconds == {mean:30, stddev:10}
  and .run_summary.with_skill.tokens == {mean:1500, stddev:500}' "$b" >/dev/null \
  && ok "with_skill aggregates" || bad "with_skill aggregates"
jq -e '.run_summary.without_skill.pass_rate == {mean:0.25, stddev:0.25}' "$b" >/dev/null \
  && ok "without_skill aggregates" || bad "without_skill aggregates"
jq -e '.run_summary.without_skill.tokens.mean == 3000
  and .run_summary.without_skill.tokens.stddev == 0' "$b" >/dev/null \
  && ok "partial token knowledge aggregates over known values" || bad "partial token knowledge aggregates over known values"
jq -e '.run_summary.delta == {pass_rate:0.5, time_seconds:-15, tokens:-1500}' "$b" >/dev/null \
  && ok "deltas subtract without from with" || bad "deltas subtract without from with"

# all-unknown cost stays null, never zero
work2="$(mktemp -d)"
cp -r "$here/lib/tests/fixtures/bench-iter" "$work2/iter"
jq '.total_tokens = null' "$work2/iter/eval-a/with_skill/timing.json" > "$work2/t.json" && mv "$work2/t.json" "$work2/iter/eval-a/with_skill/timing.json"
jq '.total_tokens = null' "$work2/iter/eval-b/with_skill/timing.json" > "$work2/t.json" && mv "$work2/t.json" "$work2/iter/eval-b/with_skill/timing.json"
jq '.total_tokens = null' "$work2/iter/eval-a/without_skill/timing.json" > "$work2/t.json" && mv "$work2/t.json" "$work2/iter/eval-a/without_skill/timing.json"
jq '.total_tokens = null' "$work2/iter/eval-b/without_skill/timing.json" > "$work2/t.json" && mv "$work2/t.json" "$work2/iter/eval-b/without_skill/timing.json"
"$here/bin/benchmark" "$work2/iter" >/dev/null 2>&1
jq -e '.run_summary.with_skill.tokens == null and .run_summary.without_skill.tokens == null
  and .run_summary.delta.tokens == null' "$work2/iter/benchmark.json" >/dev/null \
  && ok "unknown cost stays null" || bad "unknown cost stays null"
rm -rf "$work2"

exit "$fails"
