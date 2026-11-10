#!/usr/bin/env bash
# Offline test: bin/grade on recorded fixture run directories, and its rubric
# grader against the FAKE adapter only (tripwire first on PATH). No live run.
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


# --- an arm with repeated runs: <arm>/run-<k>/ is graded run by run ----------
mkdir "$work/rep"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/rep/run-1"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/rep/run-2"
printf '{"outcome":"indeterminate","reason":"timeout (exit 124)"}\n' > "$work/rep/run-2/run_status.json"
"$here/bin/grade" "$work/rep" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && jq -e '.summary.pass_rate == 0.5' "$work/rep/run-1/grading.json" >/dev/null 2>&1 \
  && jq -e '.summary.outcome == "indeterminate" and .summary.pass_rate == null' "$work/rep/run-2/grading.json" >/dev/null 2>&1 \
  && [ ! -e "$work/rep/grading.json" ] \
  && ok "an arm holding run-<k>/ directories is graded run by run" \
  || bad "an arm holding run-<k>/ directories is graded run by run (rc $rc)"
rm -rf "$work/rep/run-2/outputs"
"$here/bin/grade" "$work/rep" >"$work/rep.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q 'run-2' "$work/rep.out" \
  && ok "a run that cannot be graded fails the arm, by name" \
  || bad "a run that cannot be graded fails the arm, by name (rc $rc: $(cat "$work/rep.out"))"
mkdir "$work/empty-arm"
"$here/bin/grade" "$work/empty-arm" >"$work/empty-arm.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q 'eval-case.json' "$work/empty-arm.out" \
  && ok "a directory with neither a run nor run-<k>/ is refused" \
  || bad "a directory with neither a run nor run-<k>/ is refused (rc $rc)"
# a run that cannot be graded fails the arm (exit 2), whichever run it is, and the rest are graded
mkdir "$work/rep1"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/rep1/run-1"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/rep1/run-2"
rm -rf "$work/rep1/run-1/outputs"
"$here/bin/grade" "$work/rep1" >"$work/rep1.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q 'run-1 was not graded' "$work/rep1.out" \
  && [ ! -e "$work/rep1/run-1/grading.json" ] \
  && jq -e '.summary.pass_rate == 0.5' "$work/rep1/run-2/grading.json" >/dev/null 2>&1 \
  && ok "a first run that cannot be graded fails the arm, and the later runs are still graded" \
  || bad "a first run that cannot be graded fails the arm, and the later runs are still graded (rc $rc: $(cat "$work/rep1.out"))"
# an arm is one run or run-<k>/ directories, never both
cp -r "$here/lib/tests/fixtures/grade-run" "$work/mixed"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/mixed/run-1"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/mixed/run-2"
"$here/bin/grade" "$work/mixed" >"$work/mixed.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -qF "$work/mixed" "$work/mixed.out" && grep -q 'run-<k>' "$work/mixed.out" \
  && [ -z "$(find "$work/mixed" -name grading.json)" ] \
  && ok "an arm holding a run's files beside run-<k>/ is refused, and nothing is graded" \
  || bad "an arm holding a run's files beside run-<k>/ is refused, and nothing is graded (rc $rc: $(cat "$work/mixed.out"); graded: $(find "$work/mixed" -name grading.json | tr '\n' ' '))"
# a run directory is run-<k>, k counted from 1 and written without a leading zero
odd=""
for n in run-0 run-01 run-x run-; do
  rm -rf "$work/odd"; mkdir "$work/odd"
  cp -r "$here/lib/tests/fixtures/grade-run" "$work/odd/run-1"
  cp -r "$here/lib/tests/fixtures/grade-run" "$work/odd/$n"
  "$here/bin/grade" "$work/odd" >"$work/odd.out" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && grep -qF "$work/odd/$n" "$work/odd.out" \
    && [ -z "$(find "$work/odd" -name grading.json)" ] || odd="$odd $n(rc $rc)"
done
[ -z "$odd" ] && ok "a run- name bin/evaluate does not write is refused by name, and nothing is graded" \
  || bad "a run- name bin/evaluate does not write is refused by name, and nothing is graded (accepted:$odd)"
: > "$work/odd/run-2"; rm -rf "$work/odd/run-"
"$here/bin/grade" "$work/odd" >"$work/odd.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -qF "$work/odd/run-2 is not a directory" "$work/odd.out" \
  && ok "a run-<k> that is not a directory is refused, and says so" \
  || bad "a run-<k> that is not a directory is refused, and says so (rc $rc: $(cat "$work/odd.out"))"
# number order, not name order
mkdir "$work/ten"
for k in $(seq 1 10); do cp -r "$here/lib/tests/fixtures/grade-run" "$work/ten/run-$k"; done
rm -rf "$work/ten/run-2/outputs" "$work/ten/run-10/outputs"
"$here/bin/grade" "$work/ten" >"$work/ten.out" 2>&1
[ "$(grep -o 'run-[0-9]* was not graded' "$work/ten.out" | tr '\n' ' ')" = "run-2 was not graded run-10 was not graded " ] \
  && ok "run-2 is tried before run-10: number order, not name order" \
  || bad "run-2 is tried before run-10: number order, not name order ($(cat "$work/ten.out"))"

# --- the arm measured nothing: indeterminate short-circuits the grade --------
cp -r "$here/lib/tests/fixtures/grade-run" "$work/indet"
printf '{"outcome":"indeterminate","reason":"timeout (exit 124)"}\n' > "$work/indet/run_status.json"
"$here/bin/grade" "$work/indet" >/dev/null 2>&1
jq -e '.summary == {outcome:"indeterminate", reason:"timeout (exit 124)", passed:0, failed:0,
  needs_review:0, total:6, pass_rate:null}' "$work/indet/grading.json" >/dev/null 2>&1 \
  && ok "an indeterminate arm grades to a null pass rate, not a score" \
  || bad "an indeterminate arm grades to a null pass rate, not a score ($(cat "$work/indet/grading.json" 2>/dev/null))"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/okrun"
printf '{"outcome":"ok"}\n' > "$work/okrun/run_status.json"
"$here/bin/grade" "$work/okrun" >/dev/null 2>&1
jq -e '.summary.outcome == "ok" and .summary.pass_rate == 0.5' "$work/okrun/grading.json" >/dev/null 2>&1 \
  && ok "an ok arm is graded as usual" || bad "an ok arm is graded as usual"

# --- file-not-contains, and git-count from the recorded change list ----------
mk_case() { # $1 dir, rest: assertions — a run dir over the fixture outputs
  local d="$1"; shift
  cp -r "$here/lib/tests/fixtures/grade-run" "$d"
  jq -n --args '{id:"t", prompt:"p", expected_output:"e", assertions:$ARGS.positional}' "$@" > "$d/eval-case.json"
}
mk_case "$work/fnc" "[check:file-not-contains test.txt goodbye] no farewell" \
  "[check:file-not-contains test.txt hello] no greeting" "[check:file-not-contains absent.txt x] absent file"
"$here/bin/grade" "$work/fnc" >/dev/null 2>&1
jq -e '[.assertion_results[].passed] == [true, false, false]
  and (.assertion_results[1].evidence | test("hello"))
  and (.assertion_results[2].evidence | test("absent"))' "$work/fnc/grading.json" >/dev/null 2>&1 \
  && ok "file-not-contains passes on no match and fails on a match or an absent file" \
  || bad "file-not-contains passes on no match and fails on a match or an absent file"
mk_case "$work/gc" "[check:git-count 2] two changed" "[check:git-count 3] three changed"
printf 'app.js\ntest.txt\n' > "$work/gc/git-changed.txt"
"$here/bin/grade" "$work/gc" >/dev/null 2>&1
jq -e '[.assertion_results[].passed] == [true, false]' "$work/gc/grading.json" >/dev/null 2>&1 \
  && ok "git-count reads git-changed.txt when the run recorded one" \
  || bad "git-count reads git-changed.txt when the run recorded one"
mk_case "$work/gcgit" "[check:git-count 1] one changed" "[check:git-count 2] two changed"
( cd "$work/gcgit/outputs" && git init -q . && git add -A \
  && git -c user.name=t -c user.email=t@example.invalid commit -q -m seed && printf 'x\n' > new.txt )
"$here/bin/grade" "$work/gcgit" >/dev/null 2>&1
jq -e '[.assertion_results[].passed] == [true, false]' "$work/gcgit/grading.json" >/dev/null 2>&1 \
  && ok "git-count still falls back to outputs/.git" || bad "git-count still falls back to outputs/.git"
mk_case "$work/gcseed" "[check:git-count 3] three changed" "[check:git-count 4] four changed"
( cd "$work/gcseed/outputs" && printf 'x\n' > "a b.txt" && git init -q . && git add -A \
  && git -c user.name=t -c user.email=t@example.invalid commit -q -m seed \
  && printf 'y\n' > done.txt && git add done.txt && git rm -q app.js \
  && git -c user.name=t -c user.email=t@example.invalid commit -q -m agent && printf 'z\n' >> "a b.txt" )
"$here/bin/grade" "$work/gcseed" >/dev/null 2>&1
jq -e '[.assertion_results[].passed] == [true, false]' "$work/gcseed/grading.json" >/dev/null 2>&1 \
  && ok "the outputs/.git fallback counts against the seed commit, a spaced path once, a delete too" \
  || bad "the outputs/.git fallback counts against the seed commit, a spaced path once, a delete too ($(jq -c '[.assertion_results[].evidence]' "$work/gcseed/grading.json" 2>/dev/null))"
# No change list (none recorded, no git tree, or a tree whose seed is gone)
# is not zero changes: git-count waits for review, never passes or fails.
mk_case "$work/gcnone" "[check:git-count 0] nothing changed" "[check:git-count 1] one changed"
mk_case "$work/gcnoseed" "[check:git-count 0] nothing changed" "[check:git-count 1] one changed"
( cd "$work/gcnoseed/outputs" && git init -q . )
miss=""
for c in gcnone gcnoseed; do
  "$here/bin/grade" "$work/$c" >/dev/null 2>&1
  jq -e '[.assertion_results[].passed] == ["needs_review", "needs_review"]
    and all(.assertion_results[]; .evidence | test("change list unavailable"))' \
    "$work/$c/grading.json" >/dev/null 2>&1 || miss="$miss $c:$(jq -c '[.assertion_results[] | [.passed, .evidence]]' "$work/$c/grading.json" 2>/dev/null)"
done
[ -z "$miss" ] && ok "git-count without a change list waits for review, never counts zero" \
  || bad "git-count without a change list waits for review, never counts zero ($miss)"

# --- a check that could not run fails; an unknown verb waits for review -----
mk_case "$work/badre" "[check:file-contains test.txt (unclosed] greets" \
  "[check:file-not-contains test.txt (unclosed] no greeting"
"$here/bin/grade" "$work/badre" >/dev/null 2>&1
jq -e '[.assertion_results[].passed] == [false, false]
  and all(.assertion_results[]; .evidence | test("check could not run: invalid regex"))' \
  "$work/badre/grading.json" >/dev/null 2>&1 \
  && ok "an invalid regex fails the check for either verb, saying so" \
  || bad "an invalid regex fails the check for either verb, saying so ($(jq -c '[.assertion_results[] | [.passed, .evidence]]' "$work/badre/grading.json" 2>/dev/null))"
mk_case "$work/verbs" "[check:command-succeeds test -f nope.js] nope.js present" \
  "[check:frobnicate app.js] frobnicated"
"$here/bin/grade" "$work/verbs" >/dev/null 2>&1
jq -e '.assertion_results[0].passed == false and (.assertion_results[0].evidence | test("non-zero exit"))
  and .assertion_results[1].passed == "needs_review"
  and (.assertion_results[1].evidence | test("unknown check verb frobnicate"))' \
  "$work/verbs/grading.json" >/dev/null 2>&1 \
  && ok "a failing command fails, and an unknown verb waits for review" \
  || bad "a failing command fails, and an unknown verb waits for review"

# --- a run_status.json that exists but cannot be read is not a scored arm ----
cp -r "$here/lib/tests/fixtures/grade-run" "$work/badstatus"
printf '{"outcome": ' > "$work/badstatus/run_status.json"
"$here/bin/grade" "$work/badstatus" >/dev/null 2>&1
jq -e '.summary.outcome == "indeterminate" and .summary.pass_rate == null
  and (.summary.reason | test("run_status.json unreadable"))' "$work/badstatus/grading.json" >/dev/null 2>&1 \
  && ok "an unreadable run_status.json grades indeterminate" \
  || bad "an unreadable run_status.json grades indeterminate ($(jq -c .summary "$work/badstatus/grading.json" 2>/dev/null))"
# A status file that parses but names no outcome the lab writes (zero bytes,
# null, {}, an unknown outcome) says nothing about the arm either.
miss=""
for s in empty null obj unknown; do
  cp -r "$here/lib/tests/fixtures/grade-run" "$work/st-$s"
  case "$s" in
    empty) : > "$work/st-$s/run_status.json" ;;
    null) printf 'null\n' > "$work/st-$s/run_status.json" ;;
    obj) printf '{}\n' > "$work/st-$s/run_status.json" ;;
    unknown) printf '{"outcome": "maybe"}\n' > "$work/st-$s/run_status.json" ;;
  esac
  "$here/bin/grade" "$work/st-$s" >/dev/null 2>&1
  jq -e '.summary.outcome == "indeterminate" and .summary.pass_rate == null
    and (.summary.reason | test("run_status.json unreadable"))' "$work/st-$s/grading.json" >/dev/null 2>&1 \
    || miss="$miss $s"
done
[ -z "$miss" ] && ok "a zero-byte, null, empty, or unknown-outcome run_status.json grades indeterminate" \
  || bad "a zero-byte, null, empty, or unknown-outcome run_status.json grades indeterminate (scored:$miss)"

# --- the rubric grader, through the fake harness only ------------------------
fake_h="$here/lib/tests/fake-cli"
PATH="$here/lib/tests/tripwire:$PATH"; export PATH
own_trip="$work/tripwire.log"
outer_home="$work/outer-home"
mkdir -p "$outer_home/.config/sdlc-skills-evals/credentials/fake" "$work/outer-tmp"
printf 'token\n' > "$outer_home/.config/sdlc-skills-evals/credentials/fake/.fakerc"
rub_hook="$work/rubric-hook"
cat > "$rub_hook" <<'HOOK'
#!/usr/bin/env bash
workdir="$1"
printf 'seeded=%s outputs=%s\n' "$([ -f "$HOME/.fakerc" ] && echo yes || echo no)" \
  "$([ -f "$workdir/outputs/app.js" ] && echo yes || echo no)" >> "$RUBRIC_LOG"
ok='{"expectations":[{"text":"output is well structured","passed":false,"evidence":"RUBRIC-SAYS-NO"}]}'
case "$RUBRIC_MODE" in
  file) printf '%s\n' "$ok" > "$workdir/grading-rubric.json";;
  stdout) printf '%s\n' "$ok";;
  garbage) printf 'not json\n' > "$workdir/grading-rubric.json";;
  mismatch) printf '{"expectations":[{"text":"another claim","passed":true,"evidence":"x"}]}\n' \
              > "$workdir/grading-rubric.json";;
  nonbool) printf '{"expectations":[{"text":"output is well structured","passed":"yes","evidence":"x"}]}\n' \
              > "$workdir/grading-rubric.json";;
  fail) printf '%s\n' "$ok" > "$workdir/grading-rubric.json"; exit 1;;
esac
HOOK
chmod +x "$rub_hook"
rubric() { # $1 tag $2 mode — grades a fresh fixture copy with the rubric grader
  cp -r "$here/lib/tests/fixtures/grade-run" "$work/$1"
  TMPDIR="$work/outer-tmp" HOME="$outer_home" TRIPWIRE_LOG="$own_trip" RUBRIC_MODE="$2" \
  RUBRIC_LOG="$work/$1.log" FAKE_BEHAVIORAL_HOOK="$rub_hook" FAKE_RECORD_DIR="$work/$1.rec" \
  FAKE_SOURCE_LOG="$work/$1.src" FAKE_LAUNCH_LOG="$work/$1.launch" \
    "$here/bin/grade" "$work/$1" --harness fake --harness-dir "$fake_h" --timeout 20 >/dev/null 2>&1
}
rubric rfile file; rc=$?
jq -e '.assertion_results[5].passed == false and (.assertion_results[5].evidence | test("RUBRIC-SAYS-NO"))
  and .summary.needs_review == 0 and .summary.failed == 3 and .summary.passed == 3' \
  "$work/rfile/grading.json" >/dev/null 2>&1 && [ "$rc" -eq 0 ] \
  && ok "the rubric grader turns prose into true/false with evidence" \
  || bad "the rubric grader turns prose into true/false with evidence"
jq -e '[.assertion_results[0:5][].passed] == [true, false, true, false, true]' "$work/rfile/grading.json" >/dev/null 2>&1 \
  && ok "mechanical checks never go to the rubric" || bad "mechanical checks never go to the rubric"
p="$work/rfile.rec/call-1/prompt.txt"
grep -qF 'output is well structured' "$p" 2>/dev/null && grep -qF 'grading-rubric.json' "$p" \
  && ! grep -qF 'app.js present' "$p" \
  && ok "the grader is asked about the prose assertions only" \
  || bad "the grader is asked about the prose assertions only"
grep -qx 'seeded=yes outputs=yes' "$work/rfile.log" 2>/dev/null \
  && ok "the grader sees the outputs, in a seeded throwaway home" \
  || bad "the grader sees the outputs, in a seeded throwaway home"
g_env="$work/rfile.rec/call-1/env"
g_home="$(sed -n 's/^HOME=//p' "$g_env" 2>/dev/null)"
case "$g_home" in "$work/outer-tmp/sdlc-skills-evals/"*/home) true;; *) false;; esac \
  && grep -qx "TMPDIR=$(dirname "$g_home")/tmp" "$g_env" \
  && grep -qx "LAB_CREDENTIAL_SEED=$outer_home/.config/sdlc-skills-evals/credentials" "$g_env" \
  && grep -qx "source_home=$outer_home" "$g_env" && [ "$(grep -c . "$work/rfile.src")" = 1 ] \
  && ok "the grader runs isolated, with the adapter sourced once against the operator's home" \
  || bad "the grader runs isolated, with the adapter sourced once against the operator's home"
grep -q '^install $' "$work/rfile.launch" 2>/dev/null && ! grep -q '^install .' "$work/rfile.launch" \
  && ok "the grader is skill-free" || bad "the grader is skill-free"
[ -n "$g_home" ] && [ ! -e "$(dirname "$g_home")" ] \
  && [ -z "$(find "$work/outer-tmp" -mindepth 1 2>/dev/null | grep -v '/sdlc-skills-evals$')" ] \
  && ok "the grader leaves no run_base behind" || bad "the grader leaves no run_base behind"
rubric rstdout stdout
jq -e '.assertion_results[5].passed == false' "$work/rstdout/grading.json" >/dev/null 2>&1 \
  && ok "without the file, the verdict is read from the answer" \
  || bad "without the file, the verdict is read from the answer"
for m in garbage mismatch nonbool fail; do
  rubric "r$m" "$m"
  jq -e '.assertion_results[5].passed == "needs_review" and .summary.needs_review == 1' \
    "$work/r$m/grading.json" >/dev/null 2>&1 \
    && ok "a $m rubric answer falls back to needs_review" \
    || bad "a $m rubric answer falls back to needs_review"
done
cp -r "$here/lib/tests/fixtures/grade-run" "$work/rindet"
printf '{"outcome":"indeterminate","reason":"x"}\n' > "$work/rindet/run_status.json"
TMPDIR="$work/outer-tmp" HOME="$outer_home" TRIPWIRE_LOG="$own_trip" RUBRIC_MODE=file RUBRIC_LOG="$work/rindet.log" \
  FAKE_BEHAVIORAL_HOOK="$rub_hook" "$here/bin/grade" "$work/rindet" --harness fake --harness-dir "$fake_h" >/dev/null 2>&1
[ ! -e "$work/rindet.log" ] && ok "an indeterminate arm spends no grader call" \
  || bad "an indeterminate arm spends no grader call"
# a repeated arm spends one grader call per run that has prose
mkdir "$work/rrep"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/rrep/run-1"
cp -r "$here/lib/tests/fixtures/grade-run" "$work/rrep/run-2"
TMPDIR="$work/outer-tmp" HOME="$outer_home" TRIPWIRE_LOG="$own_trip" RUBRIC_MODE=file RUBRIC_LOG="$work/rrep.log" \
  FAKE_BEHAVIORAL_HOOK="$rub_hook" FAKE_RECORD_DIR="$work/rrep.rec" \
  FAKE_SOURCE_LOG="$work/rrep.src" FAKE_LAUNCH_LOG="$work/rrep.launch" \
    "$here/bin/grade" "$work/rrep" --harness fake --harness-dir "$fake_h" --timeout 20 >/dev/null 2>&1
[ "$(grep -c . "$work/rrep.log" 2>/dev/null)" = 2 ] \
  && jq -e '.assertion_results[5].passed == false' "$work/rrep/run-2/grading.json" >/dev/null 2>&1 \
  && ok "the rubric grader runs once per run of a repeated arm" \
  || bad "the rubric grader runs once per run of a repeated arm ($(grep -c . "$work/rrep.log" 2>/dev/null) calls)"
[ ! -s "$own_trip" ] && ok "no real agent CLI was called" || bad "no real agent CLI was called"

exit "$fails"
