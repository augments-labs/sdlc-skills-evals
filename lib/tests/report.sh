#!/usr/bin/env bash
# Offline test: bin/report copies the canonical benchmark. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/ws/iteration-1" "$work/rec"
printf '{"run_summary":{"delta":{"pass_rate":0.5}}}' > "$work/ws/iteration-1/benchmark.json"
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
printf '{"run_summary":{}}' > "$work/ws/iteration-3/benchmark.json"
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

exit "$fails"
