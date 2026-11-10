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
       plugin: {commit: (if $tree == null then null else "c0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ff" end), skill_tree: $tree},
       baseline: $base},
     runs: [], run_summary: $sum}'
}
feed=feedfeedfeedfeedfeedfeedfeedfeedfeedfeed
named='{"commit": "decafdecafdecafdecafdecafdecafdecafdecaf", "skill_tree": "beefbeefbeefbeefbeefbeefbeefbeefbeefbeef"}'
unnamed='{"commit": null, "skill_tree": null}'
mkdir -p "$work/ws/iteration-1" "$work/rec"
bench without_skill "\"$feed\"" null '{"delta":{"pass_rate":0.5}}' > "$work/ws/iteration-1/benchmark.json"
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
bench without_skill "\"$feed\"" null '{}' > "$work/ws/iteration-3/benchmark.json"
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
bench old_skill "\"$feed\"" "$unnamed" '{}' > "$work/nobase/ws/benchmark.json"
refused nobase 'old_skill' && grep -q 'metadata.baseline' "$work/nobase/out" \
  && ! grep -q 'metadata.plugin' "$work/nobase/out" \
  && ok "old_skill with a null baseline.skill_tree is refused, naming old_skill only" \
  || bad "old_skill with a null baseline.skill_tree is refused, naming old_skill only (rc $rc: $(cat "$work/nobase/out"))"
mkdir -p "$work/neither/ws"
bench old_skill null "$unnamed" '{}' > "$work/neither/ws/benchmark.json"
refused neither 'with_skill' && grep -q 'old_skill' "$work/neither/out" \
  && ok "both arms unidentified: both are named" \
  || bad "both arms unidentified: both are named (rc $rc: $(cat "$work/neither/out"))"
# a skill tree that is not a git tree hash names no text: an empty string or a
# stray word is refused like a null, and so is a record with nothing in it
mkdir -p "$work/emptytree/ws" "$work/wordtree/ws" "$work/emptybase/ws" "$work/badbase/ws" \
  "$work/emptyfile/ws" "$work/twodocs/ws" "$work/badmeta/ws"
bench without_skill '""' null '{}' > "$work/emptytree/ws/benchmark.json"
refused emptytree 'with_skill' \
  && ok "an empty-string plugin.skill_tree is refused" \
  || bad "an empty-string plugin.skill_tree is refused (rc $rc: $(cat "$work/emptytree/out"))"
bench without_skill '"feed"' null '{}' > "$work/wordtree/ws/benchmark.json"
refused wordtree 'with_skill' && grep -q 'not a git tree hash' "$work/wordtree/out" \
  && ok "a plugin.skill_tree that is not a hash is refused, and the message says so" \
  || bad "a plugin.skill_tree that is not a hash is refused, and the message says so (rc $rc: $(cat "$work/wordtree/out"))"
# a hash followed by a newline is not the hash a comparison would match
mkdir -p "$work/nltree/ws"
bench without_skill "\"$feed\\n\"" null '{}' > "$work/nltree/ws/benchmark.json"
refused nltree 'with_skill' && grep -q 'not a git tree hash' "$work/nltree/out" \
  && ok "a plugin.skill_tree with a trailing newline is refused" \
  || bad "a plugin.skill_tree with a trailing newline is refused (rc $rc: $(cat "$work/nltree/out"))"
bench old_skill "\"$feed\"" '{"commit": "c", "skill_tree": ""}' '{}' > "$work/emptybase/ws/benchmark.json"
refused emptybase 'old_skill' && ! grep -q 'with_skill' "$work/emptybase/out" \
  && ok "an empty-string baseline.skill_tree is refused, naming old_skill only" \
  || bad "an empty-string baseline.skill_tree is refused, naming old_skill only (rc $rc: $(cat "$work/emptybase/out"))"
bench old_skill "\"$feed\"" '"oops"' '{}' > "$work/badbase/ws/benchmark.json"
refused badbase 'old_skill' && ! grep -q 'with_skill' "$work/badbase/out" \
  && ok "a baseline that is not an object is refused, naming old_skill and not with_skill" \
  || bad "a baseline that is not an object is refused, naming old_skill and not with_skill (rc $rc: $(cat "$work/badbase/out"))"
: > "$work/emptyfile/ws/benchmark.json"
refused emptyfile 'with_skill' \
  && ok "an empty benchmark.json is refused" \
  || bad "an empty benchmark.json is refused (rc $rc: $(cat "$work/emptyfile/out"))"
{ bench without_skill "\"$feed\"" null '{}'; bench without_skill "\"$feed\"" null '{}'; } > "$work/twodocs/ws/benchmark.json"
refused twodocs 'with_skill' \
  && ok "a benchmark.json holding two documents is refused" \
  || bad "a benchmark.json holding two documents is refused (rc $rc: $(cat "$work/twodocs/out"))"
printf '{"metadata": "x"}\n' > "$work/badmeta/ws/benchmark.json"
refused badmeta 'with_skill' \
  && ok "metadata that is not an object is refused" \
  || bad "metadata that is not an object is refused (rc $rc: $(cat "$work/badmeta/out"))"

copied() { # $1 tag — the iteration in $work/$1/ws is recorded byte for byte
  "$here/bin/report" --workspace "$work/$1/ws" --record "$work/$1/rec" >"$work/$1/out" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && cmp -s "$work/$1/ws/benchmark.json" "$work/$1/rec/benchmark.json"
}
mkdir -p "$work/old/ws" "$work/nobaseline/ws" "$work/failing/ws"
bench old_skill "\"$feed\"" "$named" '{}' > "$work/old/ws/benchmark.json"
copied old && ok "old_skill with both skill trees named is recorded" \
  || bad "old_skill with both skill trees named is recorded (rc $rc: $(cat "$work/old/out"))"
# without_skill installs no plugin: its null baseline refuses nothing
bench without_skill "\"$feed\"" null '{}' > "$work/nobaseline/ws/benchmark.json"
copied nobaseline && ok "without_skill needs no baseline" \
  || bad "without_skill needs no baseline (rc $rc: $(cat "$work/nobaseline/out"))"
# a failing or indeterminate result is data: identified, it is recorded
bench without_skill "\"$feed\"" null '{"with_skill": {"pass_rate": null, "indeterminate_count": 2},
  "without_skill": {"pass_rate": {"mean": 1, "stddev": 0}, "indeterminate_count": 0},
  "delta": {"pass_rate": null}}' > "$work/failing/ws/benchmark.json"
copied failing && ok "an indeterminate result with a named skill text is recorded" \
  || bad "an indeterminate result with a named skill text is recorded (rc $rc: $(cat "$work/failing/out"))"

# --- a triggering summary is a record too ------------------------------------
#
# bin/report --triggering <summary.json> --record <dir> copies the summary
# bin/triggering --summary wrote to <dir>/triggering.json, under the same
# rules: an existing target refuses, and so does a summary that does not say
# which skill text it scored. One more: a record reports validation, so a
# summary without that split is not one.

# trig <plugin skill_tree|null> <splits json> — prints a summary as bin/triggering writes it
trig() {
  jq -n --argjson tree "$1" --argjson splits "$2" '
    {metadata: {skill: "probe", harness: "fake", harness_version: null, model: null,
       plugin: {commit: (if $tree == null then null else "c0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ff" end), skill_tree: $tree},
       description_sha256: "ab12", runs: 3, threshold: 0.5},
     splits: $splits,
     queries: [{query: "q", should_trigger: true, split: "validation", trigger_rate: 0, verdict: "FAIL"}]}'
}
val='{"queries": 1, "passed": 0, "failed": 1, "inconclusive": 0, "pass_rate": 0}'
trec() { # $1 tag — reports $work/$1/sum.json into $work/$1/rec; rc and output kept
  "$here/bin/report" --triggering "$work/$1/sum.json" --record "$work/$1/rec" >"$work/$1/out" 2>&1; rc=$?
}
trefused() { # $1 tag $2 pattern the refusal names — exit 2, nothing copied
  trec "$1"
  [ "$rc" -eq 2 ] && [ ! -e "$work/$1/rec" ] && grep -q "$2" "$work/$1/out"
}
for t in tgood tnull tnotree tnoval ttrain temptyval tbad ttwo texists tboth; do mkdir -p "$work/$t"; done

# a failing sheet is data: named, with its validation split, it is recorded
trig "\"$feed\"" "{\"train\": $val, \"validation\": $val}" > "$work/tgood/sum.json"
trec tgood
[ "$rc" -eq 0 ] && cmp -s "$work/tgood/sum.json" "$work/tgood/rec/triggering.json" \
  && [ "$(find "$work/tgood/rec" -type f | wc -l)" -eq 1 ] \
  && ok "a summary is copied to triggering.json, byte for byte, and nothing else is" \
  || bad "a summary is copied to triggering.json, byte for byte, and nothing else is (rc $rc: $(cat "$work/tgood/out"))"
trec tgood
[ "$rc" -eq 2 ] && grep -q 'triggering.json exists' "$work/tgood/out" \
  && ok "a second report of a summary refuses" \
  || bad "a second report of a summary refuses (rc $rc: $(cat "$work/tgood/out"))"

trig null "{\"validation\": $val}" > "$work/tnull/sum.json"
trefused tnull 'metadata.plugin.skill_tree is null' \
  && ok "a summary with a null skill tree is refused" \
  || bad "a summary with a null skill tree is refused (rc $rc: $(cat "$work/tnull/out"))"
trig '"main"' "{\"validation\": $val}" > "$work/tnotree/sum.json"
trefused tnotree 'metadata.plugin.skill_tree is not a git tree hash' \
  && ok "a summary whose skill tree is not a tree hash is refused" \
  || bad "a summary whose skill tree is not a tree hash is refused (rc $rc: $(cat "$work/tnotree/out"))"
trig "\"$feed\"" '{}' > "$work/tnoval/sum.json"
trefused tnoval 'validation' \
  && ok "a summary with no split is refused: it has no validation" \
  || bad "a summary with no split is refused: it has no validation (rc $rc: $(cat "$work/tnoval/out"))"
trig "\"$feed\"" "{\"train\": $val, \"holdout\": $val}" > "$work/ttrain/sum.json"
trefused ttrain 'validation' && ! grep -q 'skill text' "$work/ttrain/out" \
  && ok "a summary without the validation split is refused, and the named skill text is not blamed" \
  || bad "a summary without the validation split is refused, and the named skill text is not blamed (rc $rc: $(cat "$work/ttrain/out"))"
trig "\"$feed\"" '{"validation": {"queries": 0, "passed": 0, "failed": 0, "inconclusive": 0, "pass_rate": null}}' > "$work/temptyval/sum.json"
trefused temptyval 'validation' \
  && ok "a validation split with no query is refused" \
  || bad "a validation split with no query is refused (rc $rc: $(cat "$work/temptyval/out"))"
# both reasons are said at once
trig null '{}' > "$work/tboth/sum.json"
trefused tboth 'skill_tree is null' && grep -q 'validation' "$work/tboth/out" \
  && ok "an unnamed summary without validation is told both" \
  || bad "an unnamed summary without validation is told both (rc $rc: $(cat "$work/tboth/out"))"
printf 'not json\n' > "$work/tbad/sum.json"
trefused tbad 'not one JSON document' \
  && ok "a summary that is not JSON is refused" \
  || bad "a summary that is not JSON is refused (rc $rc: $(cat "$work/tbad/out"))"
{ trig "\"$feed\"" "{\"validation\": $val}"; trig "\"$feed\"" "{\"validation\": $val}"; } > "$work/ttwo/sum.json"
trefused ttwo 'not one JSON document' \
  && ok "a summary file holding two documents is refused" \
  || bad "a summary file holding two documents is refused (rc $rc: $(cat "$work/ttwo/out"))"
"$here/bin/report" --triggering "$work/no-such.json" --record "$work/tnone" >"$work/tnone.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$work/tnone" ] \
  && ok "a missing summary errors" || bad "a missing summary errors (rc $rc)"
# an existing triggering.json is kept
trig "\"$feed\"" "{\"validation\": $val}" > "$work/texists/sum.json"
mkdir -p "$work/texists/rec"; printf 'kept\n' > "$work/texists/rec/triggering.json"
trec texists
[ "$rc" -eq 2 ] && [ "$(cat "$work/texists/rec/triggering.json")" = kept ] \
  && ok "an existing triggering.json refuses with exit 2 and is kept" \
  || bad "an existing triggering.json refuses with exit 2 and is kept (rc $rc)"
# one record, one source
"$here/bin/report" --workspace "$work/ws/iteration-3" --triggering "$work/tgood/sum.json" \
  --record "$work/tmixed" >"$work/tmixed.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$work/tmixed" ] \
  && ok "--workspace and --triggering together are refused" \
  || bad "--workspace and --triggering together are refused (rc $rc)"
"$here/bin/report" --help 2>&1 | grep -q -- '--triggering' \
  && ok "--help documents --triggering" || bad "--help documents --triggering"

exit "$fails"
