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

# a zero-assertion run reads as such in benchmark.md
work4="$(mktemp -d)"
cp -r "$here/lib/tests/fixtures/bench-iter" "$work4/iter"
printf '{"assertion_results":[],"summary":{"outcome":"ok","passed":0,"failed":0,"needs_review":0,"total":0,"pass_rate":null}}\n' \
  > "$work4/iter/eval-b/with_skill/grading.json"
"$here/bin/benchmark" "$work4/iter" >/dev/null 2>&1
grep -q '| eval-b | with_skill | ok | n/a (0 assertions) |' "$work4/iter/benchmark.md" 2>/dev/null \
  && ok "benchmark.md marks a zero-assertion run n/a (0 assertions)" \
  || bad "benchmark.md marks a zero-assertion run n/a (0 assertions)"

# a grading.json missing or unreadable, or a timing.json unreadable, is an
# indeterminate row with its reason, counted, and the exit says so
cp -r "$here/lib/tests/fixtures/bench-iter" "$work4/bad"
rm "$work4/bad/eval-a/with_skill/grading.json"
printf '{"summary": ' > "$work4/bad/eval-b/with_skill/grading.json"
printf '{"duration_ms": ' > "$work4/bad/eval-a/without_skill/timing.json"
"$here/bin/benchmark" "$work4/bad" >"$work4/bad.out" 2>&1; rc=$?
bb="$work4/bad/benchmark.json"
[ "$rc" -eq 2 ] && jq -e '
  ([.runs[] | select(.outcome == "indeterminate")] | length) == 3
  and ([.runs[] | select(.eval_id == "eval-a" and .configuration == "with_skill")][0].reason | test("grading.json missing"))
  and ([.runs[] | select(.eval_id == "eval-b" and .configuration == "with_skill")][0].reason | test("grading.json unreadable"))
  and ([.runs[] | select(.eval_id == "eval-a" and .configuration == "without_skill")][0].reason | test("timing.json unreadable"))
  and all(.runs[] | select(.outcome == "indeterminate"); .pass_rate == null)
  and .run_summary.with_skill.indeterminate_count == 2
  and .run_summary.without_skill.indeterminate_count == 1' "$bb" >/dev/null 2>&1 \
  && grep -q 'indeterminate' "$work4/bad.out" && [ -s "$work4/bad/benchmark.md" ] \
  && ok "an unreadable arm record is an indeterminate row, warned, exit 2" \
  || bad "an unreadable arm record is an indeterminate row, warned, exit 2 (rc $rc; $(jq -c '[.runs[] | [.eval_id, .configuration, .outcome, .reason]]' "$bb" 2>/dev/null))"

# one iteration compares one pair
cp -r "$here/lib/tests/fixtures/bench-iter" "$work4/two"
cp -r "$work4/two/eval-b/without_skill" "$work4/two/eval-b/old_skill"
"$here/bin/benchmark" "$work4/two" >"$work4/two.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q 'two second arms' "$work4/two.out" \
  && ok "two different second arms exit 2" || bad "two different second arms exit 2 (rc $rc)"
mkdir -p "$work4/none/eval-a/with_skill"
"$here/bin/benchmark" "$work4/none" >"$work4/none.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q 'no with_skill/second-arm pairs' "$work4/none.out" \
  && ok "an iteration with no pair exits 2" || bad "an iteration with no pair exits 2 (rc $rc)"
rm -rf "$work4"

exit "$fails"
