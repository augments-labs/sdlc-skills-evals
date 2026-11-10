#!/usr/bin/env bash
# Offline test: bin/report copies the canonical benchmark. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# bench <second-arm> <plugin skill_tree|null> <baseline json> <run_summary json>
# prints a benchmark.json as bin/benchmark writes its metadata
bench() {
  jq -n --arg arm "$1" --argjson tree "$2" --argjson base "$3" --argjson sum "$4" '
    {metadata: {iteration: "iteration-1", configurations: ["with_skill", $arm], eval_ids: ["a"],
       skill: "probe", harness: "fake", harness_version: null, model: null, runs_per_eval: 1,
       plugin: {commit: (if $tree == null then null else "c0ffee" end), skill_tree: $tree},
       baseline: $base},
     runs: [], run_summary: $sum}'
}
named='{"commit": "decaf", "skill_tree": "beef"}'
unnamed='{"commit": null, "skill_tree": null}'
mkdir -p "$work/ws/iteration-1" "$work/rec"
bench without_skill '"feed"' null '{"delta":{"pass_rate":0.5}}' > "$work/ws/iteration-1/benchmark.json"
"$here/bin/report" --workspace "$work/ws/iteration-1" --record "$work/rec" >/dev/null 2>&1 \
  || { bad "report exits 0"; exit "$fails"; }
[ -f "$work/rec/benchmark.json" ] || { bad "benchmark.json copied into the record"; exit "$fails"; }
jq -e '.run_summary.delta.pass_rate == 0.5' "$work/rec/benchmark.json" >/dev/null \
  && ok "canonical copy matches the iteration" || bad "canonical copy matches the iteration"
# reruns refuse to silently overwrite: the copy is append-only evidence
"$here/bin/report" --workspace "$work/ws/iteration-1" --record "$work/rec" >/dev/null 2>&1 \
  && bad "second report refuses" || ok "second report refuses"
# missing iteration benchmark is an error, not an empty record
"$here/bin/report" --workspace "$work/ws/iteration-2" --record "$work/rec2" >/dev/null 2>&1 \
  && bad "missing benchmark errors" || ok "missing benchmark errors"


# the human summary and the reviews travel with the benchmark
mkdir -p "$work/ws/iteration-3" "$work/rec3"
bench without_skill '"feed"' null '{}' > "$work/ws/iteration-3/benchmark.json"
printf '# Benchmark\n' > "$work/ws/iteration-3/benchmark.md"
printf '{"reviews":[{"eval_id":"a","feedback":"fine"}]}\n' > "$work/ws/iteration-3/feedback.json"
"$here/bin/report" --workspace "$work/ws/iteration-3" --record "$work/rec3" >/dev/null 2>&1
cmp -s "$work/ws/iteration-3/benchmark.md" "$work/rec3/benchmark.md" \
  && cmp -s "$work/ws/iteration-3/feedback.json" "$work/rec3/feedback.json" \
  && ok "benchmark.md and feedback.json are copied when present" \
  || bad "benchmark.md and feedback.json are copied when present"
[ ! -e "$work/rec/benchmark.md" ] && [ ! -e "$work/rec/feedback.json" ] \
  && ok "absent optional files are not invented" || bad "absent optional files are not invented"
# any target already in the record refuses, with exit 2, and copies nothing
mkdir -p "$work/rec4"
printf 'kept\n' > "$work/rec4/feedback.json"
"$here/bin/report" --workspace "$work/ws/iteration-3" --record "$work/rec4" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$work/rec4/benchmark.json" ] && [ "$(cat "$work/rec4/feedback.json")" = kept ] \
  && ok "an existing target refuses with exit 2 and copies nothing" \
  || bad "an existing target refuses with exit 2 and copies nothing (rc $rc)"

# --- a record says which skill text it measured ------------------------------
# An iteration whose skill text is unidentified is refused: nothing is copied,
# and the message says which arm and why. What the run scored is not the test.
refused() { # $1 tag $2 word the message must carry — $work/$1/ws holds the iteration
  "$here/bin/report" --workspace "$work/$1/ws" --record "$work/$1/rec" >"$work/$1/out" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$work/$1/rec" ] && grep -q "$2" "$work/$1/out" \
    && grep -q 'skill_tree' "$work/$1/out"
}
mkdir -p "$work/noplugin/ws" "$work/nometa/ws" "$work/nobase/ws" "$work/notjson/ws"
bench without_skill null null '{}' > "$work/noplugin/ws/benchmark.json"
printf '# Benchmark\n' > "$work/noplugin/ws/benchmark.md"
refused noplugin 'with_skill' && grep -q 'metadata.plugin' "$work/noplugin/out" \
  && ok "a null plugin.skill_tree is refused, naming with_skill, and nothing is copied" \
  || bad "a null plugin.skill_tree is refused, naming with_skill, and nothing is copied (rc $rc: $(cat "$work/noplugin/out"))"
printf '{"run_summary":{"delta":{"pass_rate":0.5}}}' > "$work/nometa/ws/benchmark.json"
refused nometa 'with_skill' \
  && ok "a benchmark with no identity metadata is refused" \
  || bad "a benchmark with no identity metadata is refused (rc $rc: $(cat "$work/nometa/out"))"
printf 'not json' > "$work/notjson/ws/benchmark.json"
refused notjson 'with_skill' \
  && ok "a benchmark that is not JSON is refused" \
  || bad "a benchmark that is not JSON is refused (rc $rc: $(cat "$work/notjson/out"))"
bench old_skill '"feed"' "$unnamed" '{}' > "$work/nobase/ws/benchmark.json"
refused nobase 'old_skill' && grep -q 'metadata.baseline' "$work/nobase/out" \
  && ! grep -q 'metadata.plugin' "$work/nobase/out" \
  && ok "old_skill with a null baseline.skill_tree is refused, naming old_skill only" \
  || bad "old_skill with a null baseline.skill_tree is refused, naming old_skill only (rc $rc: $(cat "$work/nobase/out"))"
mkdir -p "$work/neither/ws"
bench old_skill null "$unnamed" '{}' > "$work/neither/ws/benchmark.json"
refused neither 'with_skill' && grep -q 'old_skill' "$work/neither/out" \
  && ok "both arms unidentified: both are named" \
  || bad "both arms unidentified: both are named (rc $rc: $(cat "$work/neither/out"))"

copied() { # $1 tag — the iteration in $work/$1/ws is recorded byte for byte
  "$here/bin/report" --workspace "$work/$1/ws" --record "$work/$1/rec" >"$work/$1/out" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && cmp -s "$work/$1/ws/benchmark.json" "$work/$1/rec/benchmark.json"
}
mkdir -p "$work/old/ws" "$work/nobaseline/ws" "$work/failing/ws"
bench old_skill '"feed"' "$named" '{}' > "$work/old/ws/benchmark.json"
copied old && ok "old_skill with both skill trees named is recorded" \
  || bad "old_skill with both skill trees named is recorded (rc $rc: $(cat "$work/old/out"))"
# without_skill installs no plugin: its null baseline refuses nothing
bench without_skill '"feed"' null '{}' > "$work/nobaseline/ws/benchmark.json"
copied nobaseline && ok "without_skill needs no baseline" \
  || bad "without_skill needs no baseline (rc $rc: $(cat "$work/nobaseline/out"))"
# a failing or indeterminate result is data: identified, it is recorded
bench without_skill '"feed"' null '{"with_skill": {"pass_rate": null, "indeterminate_count": 2},
  "without_skill": {"pass_rate": {"mean": 1, "stddev": 0}, "indeterminate_count": 0},
  "delta": {"pass_rate": null}}' > "$work/failing/ws/benchmark.json"
copied failing && ok "an indeterminate result with a named skill text is recorded" \
  || bad "an indeterminate result with a named skill text is recorded (rc $rc: $(cat "$work/failing/out"))"

exit "$fails"
