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


# per-eval runs and the human-readable summary
jq -e '(.runs | length) == 4
  and ([.runs[] | select(.eval_id == "eval-a" and .configuration == "with_skill")][0]
       | .pass_rate == 1 and .time_seconds == 20 and .tokens == 1000 and .outcome == "ok")
  and (.metadata.configurations == ["with_skill", "without_skill"])
  and (.metadata.eval_ids == ["eval-a", "eval-b"])
  and .run_summary.with_skill.indeterminate_count == 0' "$b" >/dev/null 2>&1 \
  && ok "runs[] holds one row per eval and arm" || bad "runs[] holds one row per eval and arm"
m="$work/iter/benchmark.md"
[ -s "$m" ] && grep -qx '## Summary' "$m" && grep -qx '## Per-Eval Breakdown' "$m" \
  && grep -q 'with_skill' "$m" && grep -q 'without_skill' "$m" && grep -q 'eval-b' "$m" \
  && ok "benchmark.md carries the summary and the per-eval breakdown" \
  || bad "benchmark.md carries the summary and the per-eval breakdown"

# indeterminate and zero-assertion runs carry no pass rate, and no mean
# divides by them
work3="$(mktemp -d)"
cp -r "$here/lib/tests/fixtures/bench-iter" "$work3/iter"
printf '{"assertion_results":[],"summary":{"outcome":"indeterminate","reason":"timeout","passed":0,"failed":0,"needs_review":0,"total":2,"pass_rate":null}}\n' \
  > "$work3/iter/eval-a/without_skill/grading.json"
printf '{"assertion_results":[],"summary":{"passed":0,"failed":0,"needs_review":0,"total":0,"pass_rate":null}}\n' \
  > "$work3/iter/eval-b/with_skill/grading.json"
"$here/bin/benchmark" "$work3/iter" >/dev/null 2>&1; rc=$?
b3="$work3/iter/benchmark.json"
jq -e '.run_summary.with_skill.pass_rate == {mean:1, stddev:0}
  and .run_summary.without_skill.pass_rate == {mean:0, stddev:0}
  and .run_summary.without_skill.indeterminate_count == 1
  and .run_summary.with_skill.indeterminate_count == 0
  and ([.runs[] | select(.outcome == "indeterminate")] | length) == 1
  and ([.runs[] | select(.pass_rate == null)] | length) == 2' "$b3" >/dev/null 2>&1 && [ "$rc" -eq 0 ] \
  && ok "null pass rates stay out of the mean and indeterminate runs are counted" \
  || bad "null pass rates stay out of the mean and indeterminate runs are counted ($(jq -c .run_summary "$b3" 2>/dev/null))"
grep -qi 'indeterminate' "$work3/iter/benchmark.md" 2>/dev/null \
  && ok "benchmark.md shows the indeterminate run" || bad "benchmark.md shows the indeterminate run"
# every run null: no division by zero, the mean is null
printf '{"assertion_results":[],"summary":{"outcome":"indeterminate","reason":"x","passed":0,"failed":0,"needs_review":0,"total":2,"pass_rate":null}}\n' \
  | tee "$work3/iter/eval-b/without_skill/grading.json" > "$work3/iter/eval-a/with_skill/grading.json"
"$here/bin/benchmark" "$work3/iter" >/dev/null 2>&1; rc=$?
jq -e '.run_summary.with_skill.pass_rate == null and .run_summary.without_skill.pass_rate == null
  and .run_summary.delta.pass_rate == null and .run_summary.without_skill.indeterminate_count == 2' \
  "$b3" >/dev/null 2>&1 && [ "$rc" -eq 0 ] \
  && ok "an arm with no scored run has a null mean, not an error" \
  || bad "an arm with no scored run has a null mean, not an error"
rm -rf "$work3"

exit "$fails"
