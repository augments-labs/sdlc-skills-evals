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

# a timing.json that parses but carries a non-number is an indeterminate row,
# never a row silently dropped from runs[] and the means
cp -r "$here/lib/tests/fixtures/bench-iter" "$work4/typed"
printf '{"total_tokens":1000,"duration_ms":"abc"}\n' > "$work4/typed/eval-a/with_skill/timing.json"
"$here/bin/benchmark" "$work4/typed" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && jq -e '(.runs | length) == 4
  and ([.runs[] | select(.eval_id == "eval-a" and .configuration == "with_skill")][0]
       | .outcome == "indeterminate" and .pass_rate == null and (.reason | test("timing.json unreadable")))' \
  "$work4/typed/benchmark.json" >/dev/null 2>&1 \
  && ok "a type-invalid timing.json is an indeterminate row, not a dropped one" \
  || bad "a type-invalid timing.json is an indeterminate row, not a dropped one (rc $rc; $(jq -c '[.runs[] | [.eval_id, .configuration, .outcome, .reason]]' "$work4/typed/benchmark.json" 2>/dev/null))"

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

# --- what the iteration measured: identity.json into metadata ----------------
# bin/evaluate writes identity.json beside the evals; bin/benchmark copies it
# into metadata next to the fields it always wrote. An iteration without one
# is still benchmarked: its identity is null, never a guess.
jq -e '.metadata | .iteration == "iter" and .configurations == ["with_skill", "without_skill"]
  and .eval_ids == ["eval-a", "eval-b"]
  and .skill == null and .harness == null and .harness_version == null and .model == null
  and .runs_per_eval == 1 and .plugin == {commit: null, skill_tree: null} and .baseline == null' "$b" >/dev/null 2>&1 \
  && ok "an iteration with no identity.json has a null identity" \
  || bad "an iteration with no identity.json has a null identity ($(jq -c .metadata "$b" 2>/dev/null))"

c1=1111111111111111111111111111111111111111; t1=2222222222222222222222222222222222222222
c2=3333333333333333333333333333333333333333; t2=4444444444444444444444444444444444444444
work5="$(mktemp -d)"
ident() { # $1 baseline json — prints an identity.json
  jq -n --arg c "$c1" --arg t "$t1" --argjson base "$1" '{skill: "probe", harness: "fake",
    harness_version: "1.2.3", model: "model-1", runs_per_eval: 1,
    plugin: {commit: $c, skill_tree: $t}, baseline: $base}'
}
cp -r "$here/lib/tests/fixtures/bench-iter" "$work5/id"
ident null > "$work5/id/identity.json"
"$here/bin/benchmark" "$work5/id" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg c "$c1" --arg t "$t1" '.metadata == {iteration: "id",
    configurations: ["with_skill", "without_skill"], eval_ids: ["eval-a", "eval-b"],
    skill: "probe", harness: "fake", harness_version: "1.2.3", model: "model-1", runs_per_eval: 1,
    plugin: {commit: $c, skill_tree: $t}, baseline: null}
  and (.runs | length) == 4 and .run_summary.delta.pass_rate == 0.5' "$work5/id/benchmark.json" >/dev/null 2>&1 \
  && ok "identity.json is copied into metadata, and is not read as an eval" \
  || bad "identity.json is copied into metadata, and is not read as an eval (rc $rc; $(jq -c .metadata "$work5/id/benchmark.json" 2>/dev/null))"

# old_skill names its baseline; without_skill has none, whatever the file says
mk_old() { # $1 dir — the fixture with old_skill as the second arm
  cp -r "$here/lib/tests/fixtures/bench-iter" "$1"
  for e in eval-a eval-b; do mv "$1/$e/without_skill" "$1/$e/old_skill"; done
}
mk_old "$work5/old"
ident "$(jq -nc --arg c "$c2" --arg t "$t2" '{commit: $c, skill_tree: $t}')" > "$work5/old/identity.json"
"$here/bin/benchmark" "$work5/old" >/dev/null 2>&1
jq -e --arg c "$c2" --arg t "$t2" '.metadata.configurations == ["with_skill", "old_skill"]
  and .metadata.baseline == {commit: $c, skill_tree: $t}' "$work5/old/benchmark.json" >/dev/null 2>&1 \
  && ok "old_skill names the baseline it installed" \
  || bad "old_skill names the baseline it installed ($(jq -c .metadata "$work5/old/benchmark.json" 2>/dev/null))"
mk_old "$work5/old-none"
"$here/bin/benchmark" "$work5/old-none" >/dev/null 2>&1
jq -e '.metadata.baseline == {commit: null, skill_tree: null}' "$work5/old-none/benchmark.json" >/dev/null 2>&1 \
  && ok "old_skill with no identity.json has a null baseline identity, not a null baseline" \
  || bad "old_skill with no identity.json has a null baseline identity, not a null baseline"
cp -r "$here/lib/tests/fixtures/bench-iter" "$work5/stray"
ident "$(jq -nc --arg c "$c2" --arg t "$t2" '{commit: $c, skill_tree: $t}')" > "$work5/stray/identity.json"
"$here/bin/benchmark" "$work5/stray" >/dev/null 2>&1
jq -e '.metadata | has("baseline") and .baseline == null' "$work5/stray/benchmark.json" >/dev/null 2>&1 \
  && ok "without_skill has no baseline" || bad "without_skill has no baseline"

# an identity.json that cannot be read is no identity, and the operator is told
cp -r "$here/lib/tests/fixtures/bench-iter" "$work5/broken"
printf '{"plugin": ' > "$work5/broken/identity.json"
"$here/bin/benchmark" "$work5/broken" >"$work5/broken.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q 'identity.json' "$work5/broken.out" \
  && jq -e '.metadata.plugin == {commit: null, skill_tree: null} and .metadata.skill == null
    and (.runs | length) == 4' "$work5/broken/benchmark.json" >/dev/null 2>&1 \
  && ok "an unreadable identity.json is a null identity, said aloud" \
  || bad "an unreadable identity.json is a null identity, said aloud (rc $rc)"
# so is one that holds anything but a single object
n=0
for content in '[]' '"x"' 'null' '{"skill":"x"}{"skill":"y"}' ''; do
  n=$((n + 1)); cp -r "$here/lib/tests/fixtures/bench-iter" "$work5/shape$n"
  printf '%s\n' "$content" > "$work5/shape$n/identity.json"
  "$here/bin/benchmark" "$work5/shape$n" >"$work5/shape$n.out" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && grep -q 'identity.json' "$work5/shape$n.out" \
    && jq -e '.metadata.plugin == {commit: null, skill_tree: null} and .metadata.skill == null
      and (.runs | length) == 4' "$work5/shape$n/benchmark.json" >/dev/null 2>&1 \
    && ok "identity.json holding '$content' is a null identity, said aloud" \
    || bad "identity.json holding '$content' is a null identity, said aloud (rc $rc: $(head -n 2 "$work5/shape$n.out"))"
done
rm -rf "$work5"

# --- repeated runs: <arm>/run-<k>/ holds one repetition ---------------------
work6="$(mktemp -d)"
mk_runs() { # $1 dir $2 runs — the fixture, each arm repeated: run-1 is the
            # fixture's arm, each later with_skill run scores 0.5 lower
  local e a k
  cp -r "$here/lib/tests/fixtures/bench-iter" "$1"
  for e in eval-a eval-b; do
    for a in with_skill without_skill; do
      mkdir "$1/$e/$a/run-1"
      mv "$1/$e/$a/grading.json" "$1/$e/$a/timing.json" "$1/$e/$a/run-1/"
      for k in $(seq 2 "$2"); do
        cp -r "$1/$e/$a/run-1" "$1/$e/$a/run-$k"
        [ "$a" = with_skill ] || continue
        jq '.summary.pass_rate -= 0.5' "$1/$e/$a/run-1/grading.json" > "$1/$e/$a/run-$k/grading.json"
      done
    done
  done
}
mk_runs "$work6/rep" 2
"$here/bin/benchmark" "$work6/rep" >/dev/null 2>&1; rc=$?
rb="$work6/rep/benchmark.json"
[ "$rc" -eq 0 ] && jq -e '(.runs | length) == 8
  and ([.runs[] | select(.eval_id == "eval-a" and .configuration == "with_skill") | [.run_number, .pass_rate]]
       == [[1, 1], [2, 0.5]])
  and ([.runs[] | select(.eval_id == "eval-b" and .configuration == "without_skill") | .run_number] == [1, 2])
  and ([.runs[] | [.eval_id, .configuration]] | unique | length) == 4' "$rb" >/dev/null 2>&1 \
  && ok "a repeated arm is one row per run, numbered" \
  || bad "a repeated arm is one row per run, numbered (rc $rc; $(jq -c '[.runs[] | [.eval_id, .configuration, .run_number, .pass_rate]]' "$rb" 2>&1))"
# with_skill scored 1, 0.5, 0.5, 0: mean 0.5, population stddev sqrt(0.125)
jq -e '.run_summary.with_skill.pass_rate.mean == 0.5
  and ((.run_summary.with_skill.pass_rate.stddev - 0.3535533905932738) | fabs) < 1e-9
  and .run_summary.with_skill.time_seconds == {mean: 30, stddev: 10}
  and .run_summary.without_skill.pass_rate == {mean: 0.25, stddev: 0.25}
  and .run_summary.delta.pass_rate == 0.25' "$rb" >/dev/null 2>&1 \
  && ok "mean and stddev run over every scored run of a configuration" \
  || bad "mean and stddev run over every scored run of a configuration ($(jq -c .run_summary "$rb" 2>&1))"
jq -e '.metadata.runs_per_eval == 2' "$rb" >/dev/null 2>&1 \
  && ok "with no identity.json, runs_per_eval is the number of runs the layout holds" \
  || bad "with no identity.json, runs_per_eval is the number of runs the layout holds ($(jq -c .metadata.runs_per_eval "$rb" 2>&1))"
jq -n '{skill: "probe", harness: "fake", runs_per_eval: 2}' > "$work6/rep/identity.json"
"$here/bin/benchmark" "$work6/rep" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && jq -e '.metadata.runs_per_eval == 2 and .metadata.skill == "probe"' "$rb" >/dev/null 2>&1 \
  && ok "an identity.json whose runs_per_eval is what the layout holds is copied" \
  || bad "an identity.json whose runs_per_eval is what the layout holds is copied (rc $rc)"
grep -qxF '| eval | configuration | run | outcome | pass rate | passed | failed | needs review | time (s) | tokens |' "$work6/rep/benchmark.md" \
  && grep -qxF '|---|---|---|---|---|---|---|---|---|---|' "$work6/rep/benchmark.md" \
  && grep -q '^| eval-a | with_skill | 2 | ok | 50% |' "$work6/rep/benchmark.md" \
  && ok "benchmark.md numbers the runs of a repeated iteration" \
  || bad "benchmark.md numbers the runs of a repeated iteration ($(grep '^| eval' "$work6/rep/benchmark.md" | head -3))"
# the single-run layout: every row is run 1, and benchmark.md is what it was
jq -e '(.runs | length) == 4 and all(.runs[]; .run_number == 1) and .metadata.runs_per_eval == 1' "$b" >/dev/null 2>&1 \
  && ok "a single-run arm is run 1" || bad "a single-run arm is run 1"
grep -qxF '| eval | configuration | outcome | pass rate | passed | failed | needs review | time (s) | tokens |' "$m" \
  && grep -qxF '|---|---|---|---|---|---|---|---|---|' "$m" \
  && grep -q '^| eval-a | with_skill | ok | 100% |' "$m" \
  && ok "benchmark.md of a single-run iteration has no run column" \
  || bad "benchmark.md of a single-run iteration has no run column"
# runs are read in number order, not name order
mk_runs "$work6/ten" 10
"$here/bin/benchmark" "$work6/ten" >/dev/null 2>&1
jq -e '[.runs[] | select(.eval_id == "eval-a" and .configuration == "with_skill") | .run_number] == [range(1; 11)]' \
  "$work6/ten/benchmark.json" >/dev/null 2>&1 \
  && ok "run-10 follows run-9" || bad "run-10 follows run-9"
# a run whose record is missing is an indeterminate row of its own
mk_runs "$work6/gap" 2
rm "$work6/gap/eval-b/with_skill/run-2/grading.json"
"$here/bin/benchmark" "$work6/gap" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && jq -e '[.runs[] | select(.outcome == "indeterminate") | [.eval_id, .configuration, .run_number, .reason]]
    == [["eval-b", "with_skill", 2, "grading.json missing"]]
  and .run_summary.with_skill.indeterminate_count == 1
  and .run_summary.with_skill.pass_rate.mean == (2 / 3)' "$work6/gap/benchmark.json" >/dev/null 2>&1 \
  && ok "a run with no grading.json is its own indeterminate row, out of the mean" \
  || bad "a run with no grading.json is its own indeterminate row, out of the mean (rc $rc)"

# --- one iteration is N runs in every arm directory --------------------------
# A layout that is not that is refused: nothing is written, the arm is named.
refused() { # $1 dir $2 text the refusal must carry — the dir holds no benchmark yet
  local out rc
  out="$("$here/bin/benchmark" "$1" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF -- "$2" \
    && [ ! -e "$1/benchmark.json" ] && [ ! -e "$1/benchmark.md" ] && return 0
  printf '%s\n' "rc $rc: $out" > "$work6/refused.out"; return 1
}
why() { tr '\n' ' ' < "$work6/refused.out"; }
# an arm holding a run's files beside run-<k>/
mk_runs "$work6/mixed" 2
cp "$work6/mixed/eval-b/with_skill/run-1/grading.json" "$work6/mixed/eval-b/with_skill/grading.json"
refused "$work6/mixed" "eval-b/with_skill" && ok "an arm holding a run's files beside run-<k>/ is refused" \
  || bad "an arm holding a run's files beside run-<k>/ is refused ($(why))"
# a run- name bin/evaluate does not write
odd=""
for n in run-0 run-01 run-x run-; do
  rm -rf "$work6/odd"; mk_runs "$work6/odd" 2
  cp -r "$work6/odd/eval-a/without_skill/run-1" "$work6/odd/eval-a/without_skill/$n"
  refused "$work6/odd" "eval-a/without_skill/$n" || odd="$odd $n($(why))"
done
[ -z "$odd" ] && ok "a run- name bin/evaluate does not write is refused by name" \
  || bad "a run- name bin/evaluate does not write is refused by name (accepted:$odd)"
# a gap in the run numbers, with and without an identity.json
mk_runs "$work6/hole" 3
rm -rf "$work6/hole/eval-b/with_skill/run-2"
refused "$work6/hole" "eval-b/with_skill holds run(s) 1, 3, not 1 to 3" \
  && ok "a missing run-<k>/ is refused: the arm, the runs it holds, and the N it should" \
  || bad "a missing run-<k>/ is refused: the arm, the runs it holds, and the N it should ($(why))"
# fewer runs than identity.json's runs_per_eval, the last one gone
mk_runs "$work6/short" 2
jq -n '{skill: "probe", harness: "fake", runs_per_eval: 3}' > "$work6/short/identity.json"
refused "$work6/short" "eval-a/with_skill holds run(s) 1, 2, not 1 to 3" \
  && ok "fewer runs than identity.json's runs_per_eval is refused" \
  || bad "fewer runs than identity.json's runs_per_eval is refused ($(why))"
# more runs than it
mk_runs "$work6/long" 2
jq -n '{skill: "probe", harness: "fake", runs_per_eval: 1}' > "$work6/long/identity.json"
refused "$work6/long" "eval-a/with_skill holds run(s) 1, 2, not 1 to 1" \
  && ok "more runs than identity.json's runs_per_eval is refused" \
  || bad "more runs than identity.json's runs_per_eval is refused ($(why))"
# one eval repeated, another not
mk_runs "$work6/uneven" 2
for a in with_skill without_skill; do
  mv "$work6/uneven/eval-b/$a/run-1/grading.json" "$work6/uneven/eval-b/$a/run-1/timing.json" "$work6/uneven/eval-b/$a/"
  rm -rf "$work6/uneven/eval-b/$a/run-1" "$work6/uneven/eval-b/$a/run-2"
done
refused "$work6/uneven" "eval-b/with_skill holds run(s) 1, not 1 to 2" \
  && ok "evals with different numbers of runs are refused" \
  || bad "evals with different numbers of runs are refused ($(why))"
# a run number too long for shell arithmetic is a number like any other
mk_runs "$work6/huge" 2
mv "$work6/huge/eval-a/with_skill/run-2" "$work6/huge/eval-a/with_skill/run-99999999999999999999"
refused "$work6/huge" "eval-a/with_skill holds run(s) 1, " \
  && ok "a run number of twenty digits is refused" \
  || bad "a run number of twenty digits is refused ($(why))"
# the right number of runs under the wrong numbers
mk_runs "$work6/skip" 2
for e in eval-a eval-b; do
  for a in with_skill without_skill; do mv "$work6/skip/$e/$a/run-2" "$work6/skip/$e/$a/run-3"; done
done
jq -n '{skill: "probe", harness: "fake", runs_per_eval: 2}' > "$work6/skip/identity.json"
refused "$work6/skip" "eval-a/with_skill holds run(s) 1, 3, not 1 to 2" \
  && ok "N runs that are not numbered 1 to N are refused" \
  || bad "N runs that are not numbered 1 to N are refused ($(why))"
# a run-<k> that is a file
mk_runs "$work6/file" 2
rm -rf "$work6/file/eval-b/without_skill/run-2"; : > "$work6/file/eval-b/without_skill/run-2"
refused "$work6/file" "eval-b/without_skill/run-2 is not a directory" \
  && ok "a run-<k> that is not a directory is refused, and says so" \
  || bad "a run-<k> that is not a directory is refused, and says so ($(why))"
# a refusal leaves an earlier benchmark.json and benchmark.md as they were, and says so
mk_runs "$work6/stale" 2
"$here/bin/benchmark" "$work6/stale" >/dev/null 2>&1
cp "$work6/stale/benchmark.json" "$work6/stale.json"; cp "$work6/stale/benchmark.md" "$work6/stale.md"
rm -rf "$work6/stale/eval-b/with_skill/run-2"
out="$("$here/bin/benchmark" "$work6/stale" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && cmp -s "$work6/stale/benchmark.json" "$work6/stale.json" && cmp -s "$work6/stale/benchmark.md" "$work6/stale.md" \
  && printf '%s' "$out" | grep -qF "$work6/stale/benchmark.json is from an earlier aggregation and is left as it was" \
  && ok "a refusal leaves an earlier benchmark.json as it was, and says it is the earlier one" \
  || bad "a refusal leaves an earlier benchmark.json as it was, and says it is the earlier one (rc $rc: $out)"
out="$("$here/bin/benchmark" "$work6/hole" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && ! printf '%s' "$out" | grep -q 'earlier aggregation' \
  && ok "a refusal with no benchmark.json names no earlier one" \
  || bad "a refusal with no benchmark.json names no earlier one (rc $rc: $out)"
# the other two refusals say it too: a mixed arm, and fewer runs than identity.json says
earlier_named() { # $1 dir, aggregated once and broken since; $1.json is the earlier benchmark.json
  local out rc      # the refusal's stderr is kept in $1.err
  out="$("$here/bin/benchmark" "$1" 2>&1 >/dev/null)"; rc=$?
  printf '%s\n' "$out" > "$1.err"
  [ "$rc" -eq 2 ] && cmp -s "$1/benchmark.json" "$1.json" \
    && printf '%s' "$out" | grep -qF "$1/benchmark.json is from an earlier aggregation and is left as it was" && return 0
  printf '%s\n' "rc $rc: $out" > "$work6/refused.out"; return 1
}
mk_runs "$work6/stale-mixed" 2
"$here/bin/benchmark" "$work6/stale-mixed" >/dev/null 2>&1; rc1=$?
cp "$work6/stale-mixed/benchmark.json" "$work6/stale-mixed.json"
cp "$work6/stale-mixed/eval-b/with_skill/run-1/grading.json" "$work6/stale-mixed/eval-b/with_skill/"
[ "$rc1" -eq 0 ] && earlier_named "$work6/stale-mixed" \
  && grep -qF "eval-b/with_skill" "$work6/stale-mixed.err" && ! grep -q 'holds run(s)' "$work6/stale-mixed.err" \
  && ok "a mixed arm's refusal says an earlier benchmark.json is the earlier one" \
  || bad "a mixed arm's refusal says an earlier benchmark.json is the earlier one (first rc $rc1; $(why))"
mk_runs "$work6/stale-id" 2
jq -n '{skill: "probe", harness: "fake", runs_per_eval: 2}' > "$work6/stale-id/identity.json"
"$here/bin/benchmark" "$work6/stale-id" >/dev/null 2>&1; rc1=$?
cp "$work6/stale-id/benchmark.json" "$work6/stale-id.json"
rm -rf "$work6/stale-id/eval-a/without_skill/run-2"
[ "$rc1" -eq 0 ] && earlier_named "$work6/stale-id" \
  && grep -qF "identity.json says runs_per_eval is 2" "$work6/stale-id.err" \
  && ok "a refusal against identity.json's runs_per_eval says an earlier benchmark.json is the earlier one" \
  || bad "a refusal against identity.json's runs_per_eval says an earlier benchmark.json is the earlier one (first rc $rc1; $(why))"
# an arm directory that is not there at all is skipped, as it is with one run
mk_runs "$work6/lone" 2
rm -rf "$work6/lone/eval-b/without_skill"
"$here/bin/benchmark" "$work6/lone" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && jq -e '[.runs[] | [.eval_id, .configuration]] | unique
    == [["eval-a", "with_skill"], ["eval-a", "without_skill"], ["eval-b", "with_skill"]]' "$work6/lone/benchmark.json" >/dev/null 2>&1 \
  && ok "an arm directory that is missing altogether is skipped, not refused" \
  || bad "an arm directory that is missing altogether is skipped, not refused (rc $rc)"
cp -r "$here/lib/tests/fixtures/bench-iter" "$work6/lone1"
rm -rf "$work6/lone1/eval-b/without_skill"
"$here/bin/benchmark" "$work6/lone1" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && jq -e '[.runs[] | [.eval_id, .configuration, .run_number]]
    == [["eval-a", "with_skill", 1], ["eval-a", "without_skill", 1], ["eval-b", "with_skill", 1]]' "$work6/lone1/benchmark.json" >/dev/null 2>&1 \
  && ok "with one run too, a missing arm directory is skipped, not refused" \
  || bad "with one run too, a missing arm directory is skipped, not refused (rc $rc)"
# a runs_per_eval that is no count names nothing: the identity is null
notn=""
for v in '"three"' 0 2.5 -1 true; do
  rm -rf "$work6/notn"; mk_runs "$work6/notn" 2
  jq -n --argjson v "$v" '{skill: "probe", harness: "fake", runs_per_eval: $v}' > "$work6/notn/identity.json"
  out="$("$here/bin/benchmark" "$work6/notn" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'identity.json is unreadable (not one JSON object, or a runs_per_eval that is not a positive integer)' \
    && jq -e '.metadata.runs_per_eval == 2 and .metadata.skill == null and .metadata.harness == null' \
         "$work6/notn/benchmark.json" >/dev/null 2>&1 || notn="$notn $v(rc $rc)"
done
[ -z "$notn" ] && ok "an identity.json whose runs_per_eval is not a positive integer is unreadable" \
  || bad "an identity.json whose runs_per_eval is not a positive integer is unreadable (copied:$notn)"
rm -rf "$work6"

exit "$fails"
