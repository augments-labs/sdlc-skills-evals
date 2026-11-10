#!/usr/bin/env bash
# Offline test: bin/evaluate — the agentskills.io paired evaluation, run
# against the FAKE adapter only.
#
# Each arm's session is FAKE_BEHAVIORAL_HOOK: it edits the staged workdir
# the way an agent would and prints an answer; a grader call (its prompt
# names grading-rubric.json) writes a rubric verdict instead. The failure
# modes an arm can hit — timeout, non-zero exit, a provider refusal, no
# model turn, a skill loaded into the skill-free arm — are driven by the
# fake's FAKE_* switches. Real agent CLIs are unreachable: the tripwire
# shims stand first on PATH, and a call to one fails and is recorded.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fake_h="$here/lib/tests/fake-cli"
export SDLC_SKILLS_EVALS_ROOT="$here"
ev="$here/bin/evaluate"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

own_trip="$work/tripwire.log"
PATH="$here/lib/tests/tripwire:$PATH"; export PATH

# --- two plugin trees and one skill's evals ----------------------------------

mk_plugin() { # $1 dir $2 marker
  mkdir -p "$1/skills/probe"
  printf -- '---\nname: probe\ndescription: "probe %s"\n---\n\n# Probe\n' "$2" > "$1/skills/probe/SKILL.md"
}
with_plug="$work/with-plugin"; mk_plugin "$with_plug" new
old_plug="$work/old-plugin"; mk_plugin "$old_plug" old

evroot="$work/evals"
mkdir -p "$evroot/probe/files/sub"
printf 'seed line\n' > "$evroot/probe/files/seed.txt"
printf 'nested\n' > "$evroot/probe/files/sub/x.txt"
cat > "$evroot/probe/evals.json" <<'JSON'
{
  "skill_name": "probe",
  "evals": [
    {
      "id": "change-seed",
      "prompt": "Edit seed.txt and add new.txt.",
      "expected_output": "seed.txt edited and new.txt created.",
      "files": ["files"],
      "assertions": [
        "[check:file-exists new.txt] new.txt is created",
        "[check:git-count 2] two files changed",
        "[check:git-count 3] the response is not a changed file",
        "[check:file-not-contains seed.txt FORBIDDEN] seed.txt stays clean",
        "the change reads well"
      ]
    },
    {
      "id": "nested-files",
      "prompt": "Look at sub/x.txt.",
      "expected_output": "sub/x.txt is read.",
      "files": ["files/sub/x.txt"],
      "assertions": ["[check:file-exists sub/x.txt] the nested file is staged"]
    },
    {
      "id": "pending",
      "prompt": "Anything.",
      "expected_output": "Not written yet.",
      "assertions": []
    }
  ]
}
JSON

# the agent: edit the workdir, answer, and record what it was given
hook="$work/hook"
cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
workdir="$1"; opening="$2"
printf 'pwd=%s seeded=%s\n' "$PWD" "$([ -f "$HOME/.fakerc" ] && echo yes || echo no)" >> "$HOOK_LOG"
if grep -q 'grading-rubric.json' "$opening"; then
  case "${RUBRIC_MODE:-file}" in
    file) printf '{"expectations":[{"text":"the change reads well","passed":true,"evidence":"RUBRIC-EVIDENCE"}]}\n' \
            > "$workdir/grading-rubric.json";;
    garbage) printf 'not json at all\n' > "$workdir/grading-rubric.json";;
  esac
  exit 0
fi
[ -f "$workdir/seed.txt" ] && printf 'edited\n' >> "$workdir/seed.txt"
printf 'new\n' > "$workdir/new.txt"
echo "done answer"
HOOK
chmod +x "$hook"

outer_home="$work/outer-home"
mkdir -p "$outer_home/.config/sdlc-skills-evals/credentials/fake"
printf 'token\n' > "$outer_home/.config/sdlc-skills-evals/credentials/fake/.fakerc"

# one evaluation, fully offline; $1 a tag naming its files. EV_HOOK replaces
# the agent for one call.
run_ev() { # $1 tag, rest: evaluate args
  local tag="$1"; shift
  mkdir -p "$work/$tag"
  HOME="$outer_home" EVALS_ROOT="$evroot" WORKSPACES_ROOT="$work/$tag/ws" \
  TRIPWIRE_LOG="$own_trip" FAKE_BEHAVIORAL_HOOK="${EV_HOOK:-$hook}" \
  FAKE_RECORD_DIR="$work/$tag/rec" FAKE_SOURCE_LOG="$work/$tag/source.log" \
  FAKE_LAUNCH_LOG="$work/$tag/launch.log" HOOK_LOG="$work/$tag/hook.log" \
    "$ev" --harness fake --harness-dir "$fake_h" --skill probe --timeout 20 "$@" \
    >"$work/$tag/out" 2>&1
}

[ -x "$ev" ] && ok "bin/evaluate is executable" || bad "bin/evaluate is executable"

# --- the dry run: the pin, the evals, the call count, nothing launched -------

dry() { # $@ evaluate args — prints the dry run's output
  HOME="$outer_home" EVALS_ROOT="$evroot" TRIPWIRE_LOG="$own_trip" \
  FAKE_SOURCE_LOG="$work/dry-source.log" FAKE_LAUNCH_LOG="$work/dry-launch.log" \
    "$ev" --harness fake --harness-dir "$fake_h" --skill probe --dry-run "$@" 2>&1
}
dry_out="$(dry --plugin "$with_plug")"; rc=$?
[ "$rc" -eq 0 ] && ok "the dry run exits 0" || bad "the dry run exits 0 (got $rc: $dry_out)"
printf '%s' "$dry_out" | grep -qF "$with_plug" && ok "the dry run names the pin" \
  || bad "the dry run names the pin"
printf '%s' "$dry_out" | grep -q 'change-seed' && printf '%s' "$dry_out" | grep -q 'nested-files' \
  && printf '%s' "$dry_out" | grep -q 'pending' \
  && ok "the dry run names every selected eval" || bad "the dry run names every selected eval"
printf '%s' "$dry_out" | grep -qE '(^|[^0-9])6 calls' \
  && ok "the dry run prices 2 x N_evals arm calls" \
  || bad "the dry run prices 2 x N_evals arm calls (got '$dry_out')"
# one eval carries a prose assertion: with the rubric grader, +1 call per arm
printf '%s' "$(dry --plugin "$with_plug" --grade-with-harness)" | grep -qE '(^|[^0-9])8 calls' \
  && ok "the dry run adds one rubric call per arm with prose assertions" \
  || bad "the dry run adds one rubric call per arm with prose assertions"
one="$(dry --plugin "$with_plug" --eval-id change-seed)"
printf '%s' "$one" | grep -qE '(^|[^0-9])2 calls' && ! printf '%s' "$one" | grep -q 'nested-files' \
  && ok "--eval-id narrows the plan to that eval" || bad "--eval-id narrows the plan to that eval ($one)"
printf '%s' "$(dry --plugin "$with_plug" --baseline-plugin "$old_plug")" | grep -qF "$old_plug" \
  && ok "the dry run names the baseline pin" || bad "the dry run names the baseline pin"
[ ! -s "$work/dry-launch.log" ] && [ ! -s "$work/dry-source.log" ] \
  && ok "the dry run sources and launches nothing" \
  || bad "the dry run sources and launches nothing"
HOME="$outer_home" EVALS_ROOT="$evroot" TRIPWIRE_LOG="$own_trip" \
  "$ev" --harness claude-code --skill probe --plugin "$with_plug" --dry-run >/dev/null 2>&1
[ ! -s "$own_trip" ] && ok "a real harness's dry run reaches no CLI" \
  || bad "a real harness's dry run reaches no CLI ($(cat "$own_trip"))"

# --- refusals before anything runs -------------------------------------------

HOME="$outer_home" EVALS_ROOT="$evroot" "$ev" --harness fake --harness-dir "$fake_h" \
  --skill nosuch --plugin "$with_plug" --dry-run >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a skill with no evals.json exits 2" || bad "a skill with no evals.json exits 2"
dry --plugin "$with_plug" --eval-id nosuch >/dev/null
[ "$?" -eq 2 ] && ok "an unknown --eval-id exits 2" || bad "an unknown --eval-id exits 2"
run_ev unrunnable --plugin "$with_plug" --harness pi --harness-dir "$here/harnesses"
[ "$?" -eq 2 ] && [ ! -s "$own_trip" ] && ok "an unrunnable harness exits 2 and calls nothing" \
  || bad "an unrunnable harness exits 2 and calls nothing"

# --- the paired run: with_skill against without_skill -------------------------

( export TMPDIR="$work/outer-tmp"; mkdir -p "$TMPDIR"
  run_ev main --plugin "$with_plug" --campaign c1; printf '%s\n' "$?" > "$work/main/rc" )
it="$work/main/ws/c1/iteration-1"
rc="$(cat "$work/main/rc")"
[ "$rc" -eq 0 ] && ok "the paired run exits 0" || bad "the paired run exits 0 (got $rc: $(tail -5 "$work/main/out"))"
missing=""
for e in change-seed nested-files pending; do
  [ -s "$it/$e/eval_metadata.json" ] || missing="$missing $e/eval_metadata.json"
  for a in with_skill without_skill; do
    for f in eval-case.json timing.json run_status.json grading.json outputs/response.txt; do
      [ -e "$it/$e/$a/$f" ] || missing="$missing $e/$a/$f"
    done
  done
done
[ -z "$missing" ] && ok "every eval and arm writes its records" || bad "every eval and arm writes its records (missing:$missing)"
jq -e '.eval_id == "change-seed" and (.assertions | length) == 5 and (.prompt | length) > 0' \
  "$it/change-seed/eval_metadata.json" >/dev/null 2>&1 \
  && ok "eval_metadata.json names the eval, its prompt and assertions" \
  || bad "eval_metadata.json names the eval, its prompt and assertions"
jq -e '(.total_tokens == null or (.total_tokens | type) == "number") and (.duration_ms | type) == "number"' \
  "$it/change-seed/with_skill/timing.json" >/dev/null 2>&1 \
  && ok "timing.json holds tokens and duration" || bad "timing.json holds tokens and duration"
n_ok="$(cat "$it"/*/*/run_status.json 2>/dev/null | jq -s '[.[] | select(.outcome == "ok")] | length')"
[ "$n_ok" = 6 ] && ok "a clean run is outcome ok on every arm" || bad "a clean run is outcome ok on every arm ($n_ok/6)"
jq -e '.exit_status == 0 and .adapter_ran == true and .skill_chain == []' \
  "$it/change-seed/without_skill/run_status.json" >/dev/null 2>&1 \
  && ok "run_status.json records the exit status, the model turn and the skill chain" \
  || bad "run_status.json records the exit status, the model turn and the skill chain (got $(cat "$it/change-seed/without_skill/run_status.json" 2>/dev/null))"
grep -qx 'done answer' "$it/change-seed/with_skill/outputs/response.txt" 2>/dev/null \
  && ok "outputs/response.txt holds the answer" || bad "outputs/response.txt holds the answer"
[ "$(cat "$it/change-seed/with_skill/git-changed.txt" 2>/dev/null)" = "$(printf 'new.txt\nseed.txt')" ] \
  && ok "git-changed.txt lists the agent's changes, recorded before response.txt" \
  || bad "git-changed.txt lists the agent's changes, recorded before response.txt (got '$(cat "$it/change-seed/with_skill/git-changed.txt" 2>/dev/null)')"
g="$it/change-seed/with_skill/grading.json"
jq -e '.assertion_results[1].passed == true and .assertion_results[2].passed == false' "$g" >/dev/null 2>&1 \
  && ok "git-count is exact end to end (response.txt does not inflate it)" \
  || bad "git-count is exact end to end (response.txt does not inflate it)"
jq -e '.assertion_results[0].passed == true and .assertion_results[3].passed == true
       and .assertion_results[4].passed == "needs_review"' "$g" >/dev/null 2>&1 \
  && ok "each arm is graded (file-not-contains, and prose waits for review)" \
  || bad "each arm is graded (file-not-contains, and prose waits for review)"
[ ! -e "$it/change-seed/with_skill/outputs/.git" ] && ok "outputs/ carries no .git" \
  || bad "outputs/ carries no .git"
[ -f "$it/change-seed/with_skill/outputs/sub/x.txt" ] && [ -f "$it/nested-files/with_skill/outputs/sub/x.txt" ] \
  && [ ! -e "$it/change-seed/with_skill/outputs/files" ] && [ ! -e "$it/nested-files/with_skill/outputs/files" ] \
  && ok "case.files entries stage into the workdir without a nested files/" \
  || bad "case.files entries stage into the workdir without a nested files/"
[ -f "$it/pending/with_skill/outputs/seed.txt" ] && [ -f "$it/pending/with_skill/outputs/sub/x.txt" ] \
  && [ -f "$it/pending/without_skill/outputs/sub/x.txt" ] && [ ! -e "$it/pending/with_skill/outputs/files" ] \
  && ok "a case with no files key still runs in the evals/<skill>/files/ project" \
  || bad "a case with no files key still runs in the evals/<skill>/files/ project"
jq -e '.summary.total == 0 and .summary.pass_rate == null' "$it/pending/with_skill/grading.json" >/dev/null 2>&1 \
  && ok "a pending_first_run eval grades to a null pass rate" \
  || bad "a pending_first_run eval grades to a null pass rate"
jq -e '(.runs | length) == 6 and .run_summary.with_skill.indeterminate_count == 0' "$it/benchmark.json" >/dev/null 2>&1 \
  && [ -s "$it/benchmark.md" ] && ok "the iteration is benchmarked (json and md)" \
  || bad "the iteration is benchmarked (json and md)"
jq -e '. == {"reviews": []}' "$it/feedback.json" >/dev/null 2>&1 \
  && ok "feedback.json is seeded empty" || bad "feedback.json is seeded empty"
[ "$(grep -c "^install $with_plug\$" "$work/main/launch.log" 2>/dev/null)" = 3 ] \
  && [ "$(grep -c '^install $' "$work/main/launch.log" 2>/dev/null)" = 3 ] \
  && ok "with_skill installs the plugin and without_skill installs none" \
  || bad "with_skill installs the plugin and without_skill installs none"

# isolation: a throwaway home under the outer TMPDIR, an exported TMPDIR
# inside it, the seed resolved from the operator's home, the adapter
# sourced once against that home — and nothing left behind
env1="$work/main/rec/call-1/env"
r_home="$(sed -n 's/^HOME=//p' "$env1" 2>/dev/null)"
r_tmp="$(sed -n 's/^TMPDIR=//p' "$env1" 2>/dev/null)"
case "$r_home" in
  "$work/outer-tmp/sdlc-skills-evals/"*/home) ok "each arm runs in a throwaway home under the outer TMPDIR";;
  *) bad "each arm runs in a throwaway home under the outer TMPDIR (HOME='$r_home')";;
esac
[ -n "$r_tmp" ] && [ "$r_tmp" = "$(dirname "$r_home")/tmp" ] && ok "the arm's TMPDIR is exported inside its base" \
  || bad "the arm's TMPDIR is exported inside its base (TMPDIR='$r_tmp')"
grep -qx "LAB_CREDENTIAL_SEED=$outer_home/.config/sdlc-skills-evals/credentials" "$env1" 2>/dev/null \
  && ok "the credential seed is exported from the operator's home" \
  || bad "the credential seed is exported from the operator's home"
[ "$(grep -c 'seeded=yes' "$work/main/hook.log" 2>/dev/null)" = 6 ] \
  && ok "every arm's home holds the seeded credential" || bad "every arm's home holds the seeded credential"
[ "$(grep -c . "$work/main/source.log" 2>/dev/null)" = 1 ] && grep -qx "sourced fake home=$outer_home" "$work/main/source.log" \
  && grep -qx "source_home=$outer_home" "$env1" 2>/dev/null \
  && ok "the adapter is sourced once, against the operator's home" \
  || bad "the adapter is sourced once, against the operator's home"
left="$(find "$work/outer-tmp" -mindepth 1 2>/dev/null | grep -v '/sdlc-skills-evals$' | head -3)"
[ -n "$r_home" ] && [ ! -e "$(dirname "$r_home")" ] && [ -z "$left" ] \
  && ok "no run_base is left behind (TMPDIR exported)" \
  || bad "no run_base is left behind (TMPDIR exported; left: $left)"

# TMPDIR unset: the bases sit under /tmp and are still removed
( unset TMPDIR; run_ev unset --plugin "$with_plug" --campaign c2 --eval-id change-seed
  printf '%s\n' "$?" > "$work/unset/rc" )
u_home="$(sed -n 's/^HOME=//p' "$work/unset/rec/call-1/env" 2>/dev/null)"
u_tmp="$(sed -n 's/^TMPDIR=//p' "$work/unset/rec/call-1/env" 2>/dev/null)"
case "$u_home" in
  /tmp/sdlc-skills-evals/*/home) ok "with TMPDIR unset the arm's home is under /tmp";;
  *) bad "with TMPDIR unset the arm's home is under /tmp (HOME='$u_home')";;
esac
[ "$(cat "$work/unset/rc")" -eq 0 ] && [ "$u_tmp" = "$(dirname "$u_home")/tmp" ] \
  && [ ! -e "$(dirname "$u_home")" ] && [ ! -e "/tmp/$(basename "$(dirname "$u_home")")" ] \
  && ok "with TMPDIR unset it is exported and nothing is left behind" \
  || bad "with TMPDIR unset it is exported and nothing is left behind"

# the next run of a campaign is the next iteration; a named one in use is refused
( export TMPDIR="$work/outer-tmp"
  HOME="$outer_home" EVALS_ROOT="$evroot" WORKSPACES_ROOT="$work/main/ws" TRIPWIRE_LOG="$own_trip" \
  FAKE_BEHAVIORAL_HOOK="$hook" HOOK_LOG="$work/main/hook2.log" \
    "$ev" --harness fake --harness-dir "$fake_h" --skill probe --timeout 20 \
      --plugin "$with_plug" --campaign c1 --eval-id pending >/dev/null 2>&1
  HOME="$outer_home" EVALS_ROOT="$evroot" WORKSPACES_ROOT="$work/main/ws" TRIPWIRE_LOG="$own_trip" \
  FAKE_BEHAVIORAL_HOOK="$hook" HOOK_LOG="$work/main/hook2.log" \
    "$ev" --harness fake --harness-dir "$fake_h" --skill probe --timeout 20 \
      --plugin "$with_plug" --campaign c1 --iteration 1 --eval-id pending >/dev/null 2>&1
  printf '%s\n' "$?" > "$work/main/rc-reuse" )
[ -d "$work/main/ws/c1/iteration-2/pending/with_skill" ] && ok "a second run is the next iteration" \
  || bad "a second run is the next iteration"
[ "$(cat "$work/main/rc-reuse")" -eq 2 ] && ok "an --iteration already holding a run is refused" \
  || bad "an --iteration already holding a run is refused"

# --- the baseline pair: with_skill against old_skill --------------------------

( export TMPDIR="$work/outer-tmp"
  run_ev old --plugin "$with_plug" --baseline-plugin "$old_plug" --campaign c3; printf '%s\n' "$?" > "$work/old/rc" )
oit="$work/old/ws/c3/iteration-1"
[ "$(cat "$work/old/rc")" -eq 0 ] && [ -d "$oit/change-seed/old_skill" ] && [ ! -e "$oit/change-seed/without_skill" ] \
  && ok "--baseline-plugin pairs with_skill against old_skill" \
  || bad "--baseline-plugin pairs with_skill against old_skill"
[ "$(grep -c "^install $old_plug\$" "$work/old/launch.log" 2>/dev/null)" = 3 ] \
  && ok "old_skill installs the baseline plugin" || bad "old_skill installs the baseline plugin"
jq -e '.run_summary | has("old_skill") and has("with_skill") and has("delta")' "$oit/benchmark.json" >/dev/null 2>&1 \
  && ok "the benchmark compares with_skill to old_skill" || bad "the benchmark compares with_skill to old_skill"
cat "$oit"/*/old_skill/run_status.json 2>/dev/null | jq -s -e 'length == 3 and all(.[]; .outcome == "ok")' >/dev/null \
  && ok "a skill chain in old_skill is expected, not contamination" \
  || bad "a skill chain in old_skill is expected, not contamination"

# --- indeterminate arms: measured nothing, so they score nothing -------------

indet() { # $1 tag $2 reason regex $3 which arms (both|without) — then the env switches
  local tag="$1" re="$2" arms="$3"; shift 3
  # shellcheck disable=SC2163  # "$@" is NAME=VALUE pairs, exported as given
  ( export TMPDIR="$work/outer-tmp"; export "$@"
    run_ev "$tag" --plugin "$with_plug" --campaign "$tag" --eval-id change-seed
    printf '%s\n' "$?" > "$work/$tag/rc" )
  local d="$work/$tag/ws/$tag/iteration-1/change-seed" w o
  w="$(jq -r '.outcome' "$d/with_skill/run_status.json" 2>/dev/null)"
  o="$(jq -r '.outcome + " " + (.reason // "")' "$d/without_skill/run_status.json" 2>/dev/null)"
  if [ "$arms" = both ]; then [ "$w" = indeterminate ]; else [ "$w" = ok ]; fi \
    && printf '%s' "$o" | grep -qiE "^indeterminate .*($re)" \
    && jq -e '.summary.outcome == "indeterminate" and .summary.pass_rate == null
              and .summary.passed == 0 and .summary.failed == 0 and .summary.total == 5' \
         "$d/without_skill/grading.json" >/dev/null 2>&1 \
    && jq -e '.run_summary.without_skill.indeterminate_count == 1 and .run_summary.without_skill.pass_rate == null' \
         "$work/$tag/ws/$tag/iteration-1/benchmark.json" >/dev/null 2>&1 \
    && [ "$(cat "$work/$tag/rc")" -eq 0 ]
}
indet timeout 'timeout|timed out' both FAKE_BEHAVIORAL_EXIT=124 \
  && ok "a timed-out arm is indeterminate" || bad "a timed-out arm is indeterminate"
indet nonzero 'exit' both FAKE_BEHAVIORAL_EXIT=3 \
  && ok "a non-zero exit is indeterminate" || bad "a non-zero exit is indeterminate"
indet auth 'refus|auth' both FAKE_AUTH_FAIL=1 \
  && ok "an auth refusal is indeterminate" || bad "an auth refusal is indeterminate"
indet quota 'refus|quota|limit' both FAKE_BEHAVIORAL_STDOUT="usage limit exceeded" \
  && ok "a quota refusal that exits 0 is indeterminate" || bad "a quota refusal that exits 0 is indeterminate"
indet noturn 'model turn|did not run' both FAKE_RAN=0 \
  && ok "an arm with no model turn is indeterminate" || bad "an arm with no model turn is indeterminate"
indet contaminated 'contaminat|skill' without FAKE_BEHAVIORAL_CHAIN=probe \
  && ok "a skill loaded into without_skill makes that arm indeterminate" \
  || bad "a skill loaded into without_skill makes that arm indeterminate"
rs() { # $1 tag $2 arm $3 jq test on that arm's run_status.json
  jq -e "$3" "$work/$1/ws/$1/iteration-1/change-seed/$2/run_status.json" >/dev/null 2>&1
}
rs timeout with_skill '.exit_status == 124' && rs nonzero with_skill '.exit_status == 3' \
  && rs noturn with_skill '.adapter_ran == false' \
  && rs contaminated without_skill '.skill_chain == ["probe"] and .adapter_ran == true' \
  && ok "run_status.json carries the evidence behind each indeterminate verdict" \
  || bad "run_status.json carries the evidence behind each indeterminate verdict"

# --- the rubric grader, through the harness ----------------------------------

( export TMPDIR="$work/outer-tmp"
  run_ev rubric --plugin "$with_plug" --campaign c4 --eval-id change-seed --grade-with-harness
  printf '%s\n' "$?" > "$work/rubric/rc" )
rg="$work/rubric/ws/c4/iteration-1/change-seed/with_skill/grading.json"
[ "$(cat "$work/rubric/rc")" -eq 0 ] \
  && jq -e '.assertion_results[4].passed == true and (.assertion_results[4].evidence | test("RUBRIC-EVIDENCE"))' "$rg" >/dev/null 2>&1 \
  && ok "--grade-with-harness grades prose through the harness" \
  || bad "--grade-with-harness grades prose through the harness"
[ "$(find "$work/rubric/rec" -mindepth 1 -maxdepth 1 -name 'call-*' 2>/dev/null | wc -l)" -eq 4 ] \
  && ok "the rubric adds one call per arm, as the dry run priced" \
  || bad "the rubric adds one call per arm, as the dry run priced"

# --- what the agent changed, against the seed; a files/<dir> entry ---------
# The agent commits one file, renames one through git, deletes one, and
# edits a path with a space: every change counts against the seed commit,
# a rename by its destination. "files/src" stages src/ once, not src/src.

cevroot="$work/cevals"
mkdir -p "$cevroot/probe/files/src"
for f in old.txt gone.txt "my file.txt" src/a.txt; do printf 'seed of %s\n' "$f" > "$cevroot/probe/files/$f"; done
cat > "$cevroot/probe/evals.json" <<'JSON'
{"skill_name": "probe", "evals": [{"id": "changes", "prompt": "Change things.",
  "expected_output": "Things changed.", "files": ["files/src"],
  "assertions": ["[check:git-count 4] four files changed"]}]}
JSON
chook="$work/chook"
cat > "$chook" <<'HOOK'
#!/usr/bin/env bash
cd "$1" || exit 1
printf 'c\n' > committed.txt && git add committed.txt \
  && git -c user.name=a -c user.email=a@example.invalid commit -q -m agent
git mv old.txt renamed.txt && rm gone.txt && printf 'edit\n' >> "my file.txt"
echo "done answer"
HOOK
chmod +x "$chook"
( export TMPDIR="$work/outer-tmp"
  HOME="$outer_home" EVALS_ROOT="$cevroot" WORKSPACES_ROOT="$work/changes/ws" TRIPWIRE_LOG="$own_trip" \
  FAKE_BEHAVIORAL_HOOK="$chook" FAKE_RECORD_DIR="$work/changes/rec" \
    "$ev" --harness fake --harness-dir "$fake_h" --skill probe --timeout 20 \
      --plugin "$with_plug" --campaign c5 >/dev/null 2>&1 )
ca="$work/changes/ws/c5/iteration-1/changes/with_skill"
[ "$(cat "$ca/git-changed.txt" 2>/dev/null)" = "$(printf 'committed.txt\ngone.txt\nmy file.txt\nrenamed.txt')" ] \
  && jq -e '.assertion_results[0].passed == true' "$ca/grading.json" >/dev/null 2>&1 \
  && ok "git-changed.txt lists every change against the seed, a rename by its destination" \
  || bad "git-changed.txt lists every change against the seed, a rename by its destination (got '$(cat "$ca/git-changed.txt" 2>/dev/null)')"
[ -f "$ca/outputs/src/a.txt" ] && [ ! -e "$ca/outputs/src/src" ] \
  && ok "a files/<dir> entry stages the directory once, not nested in itself" \
  || bad "a files/<dir> entry stages the directory once, not nested in itself ($(cd "$ca/outputs" 2>/dev/null && find src | tr '\n' ' '))"

# --- an agent that replaces the repository: the seed is gone ---------------
# The change list cannot be computed, so none is recorded and the operator is
# told; git-count then waits for review instead of counting zero.
levroot="$work/levals"
mkdir -p "$levroot/probe/files"
printf 'seed\n' > "$levroot/probe/files/seed.txt"
cat > "$levroot/probe/evals.json" <<'JSON'
{"skill_name": "probe", "evals": [{"id": "lost", "prompt": "Start over.",
  "expected_output": "A fresh repository.", "files": ["files/seed.txt"],
  "assertions": ["[check:git-count 0] nothing changed"]}]}
JSON
lhook="$work/lhook"
cat > "$lhook" <<'HOOK'
#!/usr/bin/env bash
cd "$1" || exit 1
rm -rf .git && git init -q . && printf 'n\n' > new.txt
echo "done answer"
HOOK
chmod +x "$lhook"; mkdir -p "$work/lost"
( export TMPDIR="$work/outer-tmp"
  HOME="$outer_home" EVALS_ROOT="$levroot" WORKSPACES_ROOT="$work/lost/ws" TRIPWIRE_LOG="$own_trip" \
  FAKE_BEHAVIORAL_HOOK="$lhook" FAKE_RECORD_DIR="$work/lost/rec" \
    "$ev" --harness fake --harness-dir "$fake_h" --skill probe --timeout 20 \
      --plugin "$with_plug" --campaign c6 >/dev/null 2>"$work/lost/err.txt" )
la="$work/lost/ws/c6/iteration-1/lost/with_skill"
[ -d "$la/outputs" ] && [ ! -e "$la/git-changed.txt" ] \
  && grep -q 'lost/with_skill: change list unavailable' "$work/lost/err.txt" 2>/dev/null \
  && jq -e '.assertion_results[0].passed == "needs_review"
    and (.assertion_results[0].evidence | test("change list unavailable"))' "$la/grading.json" >/dev/null 2>&1 \
  && ok "a lost seed records no change list, says so, and git-count waits for review" \
  || bad "a lost seed records no change list, says so, and git-count waits for review (git-changed: '$(cat "$la/git-changed.txt" 2>/dev/null)'; $(jq -c '.assertion_results' "$la/grading.json" 2>/dev/null))"

# --- identity.json: which skill text each arm installed ----------------------
# A plugin checkout with two commits of the probe skill, a tag on the second,
# and a clone of it to dirty mid-run.
gitplug="$work/git-plugin"
gp() { git -C "$gitplug" -c user.name=t -c user.email=t@example.invalid "$@"; }
mkdir -p "$gitplug/skills/testing/probe"
printf -- '---\nname: probe\ndescription: "probe one"\n---\n' > "$gitplug/skills/testing/probe/SKILL.md"
git -C "$gitplug" init -q && gp add -A && gp commit -q -m one
c_one="$(gp rev-parse HEAD)"; t_one="$(gp rev-parse HEAD:skills/testing/probe)"
printf -- '---\nname: probe\ndescription: "probe two"\n---\n' > "$gitplug/skills/testing/probe/SKILL.md"
gp add -A && gp commit -q -m two && gp tag v2
c_two="$(gp rev-parse HEAD)"; t_two="$(gp rev-parse HEAD:skills/testing/probe)"
dirtied="$work/git-plugin-dirtied"
git clone -q "$gitplug" "$dirtied"

# the agent, naming its model first: MODEL_NAME, or a different one per call
mhook="$work/model-hook"
cat > "$mhook" <<'HOOK'
#!/usr/bin/env bash
echo call >> "$HOOK_LOG"
if [ -z "${MODEL_ONCE:-}" ] || [ "$(wc -l < "$HOOK_LOG")" -eq 1 ]; then
  printf 'MODEL %s\n' "${MODEL_NAME:-model-$(wc -l < "$HOOK_LOG")}"
fi
[ -z "${DIRTY_PLUGIN:-}" ] || printf 'edited mid-run\n' >> "$DIRTY_PLUGIN/skills/testing/probe/SKILL.md"
echo "done answer"
HOOK
chmod +x "$mhook"
idrun() { # $1 tag, rest: evaluate args — one eval, under its own outer TMPDIR
  local tag="$1"; shift
  ( export TMPDIR="$work/outer-tmp"; run_ev "$tag" --eval-id nested-files --campaign "$tag" "$@" )
}
idit() { printf '%s\n' "$work/$1/ws/$1/iteration-1"; }
report_to() { # $1 tag — bin/report of that iteration into a fresh record
  "$here/bin/report" --workspace "$(idit "$1")" --record "$work/$1/record" >"$work/$1/report.out" 2>&1
}

# a directory that is no git work tree: the arm ran, its text has no name
idrun idnone --plugin "$with_plug"; rc=$?
[ "$rc" -eq 0 ] && jq -e '. == {skill: "probe", harness: "fake", harness_version: null, model: null,
    runs_per_eval: 1, plugin: {commit: null, skill_tree: null}, baseline: null}' \
    "$(idit idnone)/identity.json" >/dev/null 2>&1 \
  && ok "a plugin directory outside git runs, and identity.json names no skill text" \
  || bad "a plugin directory outside git runs, and identity.json names no skill text (rc $rc; $(jq -c . "$(idit idnone)/identity.json" 2>&1))"
jq -e '.metadata | .iteration == "iteration-1" and .configurations == ["with_skill", "without_skill"]
    and .eval_ids == ["nested-files"] and .skill == "probe" and .harness == "fake"
    and .plugin == {commit: null, skill_tree: null}' "$(idit idnone)/benchmark.json" >/dev/null 2>&1 \
  && ok "the benchmark carries the identity beside the fields it always had" \
  || bad "the benchmark carries the identity beside the fields it always had ($(jq -c .metadata "$(idit idnone)/benchmark.json" 2>&1))"
grep -q 'with_skill.*unidentified (.*work tree.*bin/report' "$work/idnone/out" \
  && ok "the run says with_skill is unidentified, why, and that bin/report will refuse it" \
  || bad "the run says with_skill is unidentified, why, and that bin/report will refuse it ($(grep -i identi "$work/idnone/out"))"
report_to idnone; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$work/idnone/record" ] \
  && ok "bin/report refuses the unidentified iteration" \
  || bad "bin/report refuses the unidentified iteration (rc $rc)"

# a clean git work tree: HEAD and the skill's tree hash, the CLI version, the model
MODEL_NAME=model-x FAKE_VERSION=9.8.7 EV_HOOK="$mhook" idrun idgit --plugin "$gitplug"; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg c "$c_two" --arg t "$t_two" '. == {skill: "probe", harness: "fake",
    harness_version: "9.8.7", model: "model-x", runs_per_eval: 1,
    plugin: {commit: $c, skill_tree: $t}, baseline: null}' "$(idit idgit)/identity.json" >/dev/null 2>&1 \
  && ok "a clean git work tree is HEAD and the skill's tree hash, with the CLI version and the model" \
  || bad "a clean git work tree is HEAD and the skill's tree hash, with the CLI version and the model (rc $rc; $(jq -c . "$(idit idgit)/identity.json" 2>&1))"
grep -q 'unidentified' "$work/idgit/out" && bad "an identified run prints no warning" \
  || ok "an identified run prints no warning"
report_to idgit; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg t "$t_two" '.metadata.plugin.skill_tree == $t' \
    "$work/idgit/record/benchmark.json" >/dev/null 2>&1 \
  && ok "bin/report records the identified iteration" \
  || bad "bin/report records the identified iteration (rc $rc: $(cat "$work/idgit/report.out"))"

# refs: a tag is the commit under it; old_skill names its baseline
SDLC_SKILLS_ROOT="$gitplug" idrun idref --plugin v2 --baseline-plugin "$c_one"; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg c "$c_two" --arg t "$t_two" --arg bc "$c_one" --arg bt "$t_one" '
    .plugin == {commit: $c, skill_tree: $t} and .baseline == {commit: $bc, skill_tree: $bt}' \
    "$(idit idref)/identity.json" >/dev/null 2>&1 \
  && jq -e --arg bt "$t_one" '.metadata.configurations == ["with_skill", "old_skill"]
    and .metadata.baseline.skill_tree == $bt' "$(idit idref)/benchmark.json" >/dev/null 2>&1 \
  && ok "refs are named by full commit and skill tree, for with_skill and old_skill" \
  || bad "refs are named by full commit and skill tree, for with_skill and old_skill (rc $rc; $(jq -c . "$(idit idref)/identity.json" 2>&1))"

# old_skill on a directory outside git: the baseline is the unnamed one
idrun idbase --plugin "$gitplug" --baseline-plugin "$old_plug"; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg t "$t_two" '.plugin.skill_tree == $t
    and .baseline == {commit: null, skill_tree: null}' "$(idit idbase)/identity.json" >/dev/null 2>&1 \
  && grep -q 'old_skill.*unidentified' "$work/idbase/out" && ! grep -q 'with_skill.*unidentified' "$work/idbase/out" \
  && ok "an unnamed baseline is null, and only old_skill is warned about" \
  || bad "an unnamed baseline is null, and only old_skill is warned about (rc $rc; $(jq -c . "$(idit idbase)/identity.json" 2>&1))"
report_to idbase; rc=$?
[ "$rc" -eq 2 ] && grep -q 'old_skill' "$work/idbase/report.out" \
  && ok "bin/report refuses it, naming old_skill" || bad "bin/report refuses it, naming old_skill (rc $rc)"

# two arms that name different models: the iteration names none
EV_HOOK="$mhook" idrun idmodels --plugin "$gitplug"
jq -e --arg t "$t_two" '.model == null and .plugin.skill_tree == $t' "$(idit idmodels)/identity.json" >/dev/null 2>&1 \
  && [ "$(grep -h '^MODEL ' "$(idit idmodels)"/nested-files/*/stream.txt | sort -u | wc -l)" -eq 2 ] \
  && ok "arms that name different models record a null model, not one of them" \
  || bad "arms that name different models record a null model, not one of them ($(jq -c . "$(idit idmodels)/identity.json" 2>&1))"

# one arm names its model and the other names none: the iteration names none
MODEL_NAME=model-x MODEL_ONCE=1 EV_HOOK="$mhook" idrun idsome --plugin "$gitplug"
jq -e --arg t "$t_two" '.model == null and .plugin.skill_tree == $t' "$(idit idsome)/identity.json" >/dev/null 2>&1 \
  && [ "$(grep -h '^MODEL ' "$(idit idsome)"/nested-files/*/stream.txt | wc -l)" -eq 1 ] \
  && ok "a model only some arms named is not recorded for the iteration" \
  || bad "a model only some arms named is not recorded for the iteration ($(jq -c . "$(idit idsome)/identity.json" 2>&1))"

# a session whose outputs could not be copied still ran, so the model it named
# counts: here it differs from the other arm's, and the iteration names none
gonehook="$work/gone-hook.sh"
cat > "$gonehook" <<'HOOK'
#!/usr/bin/env bash
echo call >> "$HOOK_LOG"
n="$(wc -l < "$HOOK_LOG")"
printf 'MODEL model-%s\n' "$n"
echo "done answer"
[ "$n" -eq 1 ] || rm -rf "$1"
HOOK
chmod +x "$gonehook"
EV_HOOK="$gonehook" idrun idgone --plugin "$gitplug"; rc=$?
[ "$rc" -eq 2 ] && grep -q 'nested-files/without_skill' "$work/idgone/out" \
  && [ ! -e "$(idit idgone)/nested-files/without_skill/grading.json" ] \
  && [ "$(grep -h '^MODEL ' "$(idit idgone)"/nested-files/*/stream.txt | sort -u | wc -l)" -eq 2 ] \
  && jq -e --arg t "$t_two" '.model == null and .plugin.skill_tree == $t' "$(idit idgone)/identity.json" >/dev/null 2>&1 \
  && ok "an arm whose outputs were lost still counts its session's model" \
  || bad "an arm whose outputs were lost still counts its session's model (rc $rc; $(jq -c . "$(idit idgone)/identity.json" 2>&1); $(tail -n 3 "$work/idgone/out"))"

# skill text edited while the run was under way: what the arms saw is no commit's
MODEL_NAME=model-x DIRTY_PLUGIN="$dirtied" EV_HOOK="$mhook" idrun iddirty --plugin "$dirtied"; rc=$?
[ "$rc" -eq 0 ] && jq -e '.plugin == {commit: null, skill_tree: null}' "$(idit iddirty)/identity.json" >/dev/null 2>&1 \
  && grep -q 'with_skill.*unidentified' "$work/iddirty/out" \
  && ok "a plugin edited during the run ends unidentified" \
  || bad "a plugin edited during the run ends unidentified (rc $rc; $(jq -c . "$(idit iddirty)/identity.json" 2>&1))"
# the same for the baseline: old_skill ends unidentified, with_skill stays named
dirtied2="$work/git-plugin-dirtied2"
git clone -q "$gitplug" "$dirtied2"
MODEL_NAME=model-x DIRTY_PLUGIN="$dirtied2" EV_HOOK="$mhook" idrun idbasedirty --plugin "$gitplug" --baseline-plugin "$dirtied2"; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg t "$t_two" '.plugin.skill_tree == $t
    and .baseline == {commit: null, skill_tree: null}' "$(idit idbasedirty)/identity.json" >/dev/null 2>&1 \
  && grep -q 'old_skill.*unidentified.*changed during the run' "$work/idbasedirty/out" \
  && ! grep -q 'with_skill.*unidentified' "$work/idbasedirty/out" \
  && ok "a baseline edited during the run ends unidentified, and with_skill stays named" \
  || bad "a baseline edited during the run ends unidentified, and with_skill stays named (rc $rc; $(jq -c . "$(idit idbasedirty)/identity.json" 2>&1))"
report_to idbasedirty; rc=$?
[ "$rc" -eq 2 ] && grep -q 'old_skill' "$work/idbasedirty/report.out" && ! grep -q 'with_skill' "$work/idbasedirty/report.out" \
  && ok "bin/report refuses that iteration, naming old_skill only" \
  || bad "bin/report refuses that iteration, naming old_skill only (rc $rc: $(cat "$work/idbasedirty/report.out"))"

# the dry run says, before anything is spent, whether the run can be recorded
dry_id="$(dry --plugin "$gitplug")"
printf '%s\n' "$dry_id" | grep -q "^identity : with_skill $c_two  skill_tree $t_two\$" \
  && ok "the dry run names with_skill's commit and skill tree" \
  || bad "the dry run names with_skill's commit and skill tree (got '$dry_id')"
dry_id="$(dry --plugin "$with_plug" --baseline-plugin "$gitplug")"
printf '%s\n' "$dry_id" | grep -q '^identity : with_skill unidentified.*bin/report' \
  && printf '%s\n' "$dry_id" | grep -q "^identity : old_skill $c_two  skill_tree $t_two\$" \
  && ok "the dry run says which arm is unidentified, and names the other" \
  || bad "the dry run says which arm is unidentified, and names the other (got '$dry_id')"
[ "$(dry --plugin "$with_plug" | grep -c '^identity :')" -eq 1 ] \
  && [ "$(dry --plugin "$with_plug" --baseline-plugin "$gitplug" | grep -c '^identity :')" -eq 2 ] \
  && ok "the dry run prints one identity line per arm that installs a plugin, none for without_skill" \
  || bad "the dry run prints one identity line per arm that installs a plugin, none for without_skill"

# a commit installed as files that are not its tree's: a plugin checkout set
# to convert line endings extracts the commit converted, so the arm ran on
# text no tree names
convplug="$work/conv-plugin"
git clone -q "$gitplug" "$convplug" && git -C "$convplug" config core.autocrlf true
SDLC_SKILLS_ROOT="$convplug" idrun idconv --plugin "$c_two"; rc=$?
[ "$rc" -eq 0 ] && jq -e --arg c "$c_two" '.plugin == {commit: $c, skill_tree: null}' \
    "$(idit idconv)/identity.json" >/dev/null 2>&1 \
  && grep -q 'with_skill unidentified (.*SKILL\.md does not hold the bytes the tree holds.*bin/report' "$work/idconv/out" \
  && ! grep -q 'the tree changed during the run' "$work/idconv/out" \
  && ok "a commit installed with converted line endings keeps its commit and names no skill tree, and the run says which file" \
  || bad "a commit installed with converted line endings keeps its commit and names no skill tree, and the run says which file (rc $rc; $(jq -c . "$(idit idconv)/identity.json" 2>&1): $(grep identity "$work/idconv/out"))"
dry_id="$(SDLC_SKILLS_ROOT="$convplug" dry --plugin "$c_two")"
printf '%s\n' "$dry_id" | grep -q "^identity : with_skill $c_two  skill_tree $t_two\$" \
  && ok "the dry run installs nothing: it prints the identity the commit names" \
  || bad "the dry run installs nothing: it prints the identity the commit names (got '$dry_id')"

# --- --runs N: each eval and arm is repeated N times --------------------------

dry3="$(dry --plugin "$with_plug" --runs 3)"
printf '%s' "$dry3" | grep -qE '(^|[^0-9])18 calls' \
  && printf '%s\n' "$dry3" | grep -qx 'budget   : 3 eval(s) x 2 arms x 3 runs = 18 arm calls' \
  && ok "the dry run prices evals x arms x runs" || bad "the dry run prices evals x arms x runs (got '$dry3')"
printf '%s' "$(dry --plugin "$with_plug" --runs 3 --grade-with-harness)" | grep -qE '(^|[^0-9])24 calls' \
  && ok "the dry run prices one rubric call per arm with prose, per run" \
  || bad "the dry run prices one rubric call per arm with prose, per run"
[ "$(dry --plugin "$with_plug" --runs 1)" = "$dry_out" ] \
  && [ "$(dry --plugin "$with_plug" --runs 1 --grade-with-harness)" = "$(dry --plugin "$with_plug" --grade-with-harness)" ] \
  && ok "--runs 1 plans what no --runs plans, to the byte" || bad "--runs 1 plans what no --runs plans, to the byte"
bad_runs=""
for v in 0 x -1 1.5 ''; do
  dry --plugin "$with_plug" --runs "$v" >/dev/null; [ "$?" -eq 2 ] || bad_runs="$bad_runs '$v'"
done
[ -z "$bad_runs" ] && ok "--runs needs a positive integer" || bad "--runs needs a positive integer (accepted:$bad_runs)"
"$ev" --help | grep -q -- '--runs N' && ok "--help names --runs" || bad "--help names --runs"

idrun runs2 --plugin "$gitplug" --runs 2; rc=$?
rit="$(idit runs2)"
missing=""
for a in with_skill without_skill; do
  for k in 1 2; do
    for f in eval-case.json timing.json run_status.json grading.json outputs/response.txt; do
      [ -e "$rit/nested-files/$a/run-$k/$f" ] || missing="$missing $a/run-$k/$f"
    done
  done
  [ ! -e "$rit/nested-files/$a/grading.json" ] && [ ! -e "$rit/nested-files/$a/outputs" ] \
    && [ ! -e "$rit/nested-files/$a/run-3" ] || missing="$missing $a:stray"
done
[ "$rc" -eq 0 ] && [ -z "$missing" ] && ok "--runs 2 writes each repetition under <arm>/run-<k>/" \
  || bad "--runs 2 writes each repetition under <arm>/run-<k>/ (rc $rc; missing:$missing; $(tail -3 "$work/runs2/out"))"
[ "$(grep -c . "$work/runs2/hook.log" 2>/dev/null)" = 4 ] \
  && [ "$(grep -c "^install $gitplug\$" "$work/runs2/launch.log" 2>/dev/null)" = 2 ] \
  && ok "--runs 2 makes evals x arms x 2 calls" \
  || bad "--runs 2 makes evals x arms x 2 calls ($(grep -c . "$work/runs2/hook.log" 2>/dev/null) sessions)"
jq -e '.runs_per_eval == 2' "$rit/identity.json" >/dev/null 2>&1 \
  && jq -e '.metadata.runs_per_eval == 2 and (.runs | length) == 4
    and ([.runs[] | [.configuration, .run_number]]
         == [["with_skill", 1], ["with_skill", 2], ["without_skill", 1], ["without_skill", 2]])
    and all(.runs[]; .outcome == "ok" and .pass_rate == 1)
    and .run_summary.with_skill.pass_rate == {mean: 1, stddev: 0}' "$rit/benchmark.json" >/dev/null 2>&1 \
  && ok "the benchmark holds one numbered row per run, and runs_per_eval is N" \
  || bad "the benchmark holds one numbered row per run, and runs_per_eval is N ($(jq -c '[.metadata.runs_per_eval, .runs]' "$rit/benchmark.json" 2>&1))"
report_to runs2; rc=$?
[ "$rc" -eq 0 ] && jq -e '.metadata.runs_per_eval == 2' "$work/runs2/record/benchmark.json" >/dev/null 2>&1 \
  && ok "bin/report records a repeated iteration, runs_per_eval with it" || bad "bin/report records a repeated iteration, runs_per_eval with it (rc $rc)"

# --runs 1 is the layout and the output of no --runs
idrun runs1 --plugin "$gitplug" --runs 1; rc1=$?
idrun runs0 --plugin "$gitplug"; rc0=$?
tree_of() { ( cd "$(idit "$1")" && find . | sort ); }
said() { sed -e "s#$work/$1/#W/#g" -e "s#/$1/#/T/#g" "$work/$1/out"; }
[ "$rc1" -eq 0 ] && [ "$rc0" -eq 0 ] && [ "$(tree_of runs1)" = "$(tree_of runs0)" ] \
  && [ -z "$(find "$(idit runs1)" -name 'run-*')" ] \
  && [ -f "$(idit runs1)/nested-files/with_skill/grading.json" ] \
  && ok "--runs 1 keeps the single-run layout" || bad "--runs 1 keeps the single-run layout (rc $rc1/$rc0)"
[ "$(said runs1)" = "$(said runs0)" ] && [ -s "$work/runs1/out" ] \
  && ok "--runs 1 says what no --runs says" \
  || bad "--runs 1 says what no --runs says ($(diff <(said runs1) <(said runs0) | head -4))"
jq -e '.runs_per_eval == 1' "$(idit runs1)/identity.json" >/dev/null 2>&1 \
  && jq -e 'all(.runs[]; .run_number == 1)' "$(idit runs1)/benchmark.json" >/dev/null 2>&1 \
  && ok "a single run is run 1 of 1" || bad "a single run is run 1 of 1"

# one run says, word for word, what it said before --runs existed
dry_g="$(dry --plugin "$with_plug" --grade-with-harness)"
printf '%s\n' "$dry_out" | grep -qxF 'budget   : 3 eval(s) x 2 arms = 6 arm calls' \
  && printf '%s\n' "$dry_out" | grep -qxF 'at most 6 calls total, billed to your own harness account.' \
  && printf '%s\n' "$dry_g" | grep -qxF 'budget   : 3 eval(s) x 2 arms = 6 arm calls' \
  && printf '%s\n' "$dry_g" | grep -qxF '         + 2 rubric grader call(s) (1 eval(s) with prose x 2 arms)' \
  && printf '%s\n' "$dry_g" | grep -qxF 'at most 8 calls total, billed to your own harness account.' \
  && ok "one run is priced in the words used before --runs" \
  || bad "one run is priced in the words used before --runs ($(printf '%s\n' "$dry_g" | grep -E 'budget|rubric|at most' | tr '\n' ';'))"
one_said=$'nested-files/with_skill: running\nnested-files/without_skill: running'
[ "$(grep ': running$' "$work/runs0/out")" = "$one_said" ] && [ "$(grep ': running$' "$work/runs1/out")" = "$one_said" ] \
  && ! grep -q '/run-[0-9]' "$work/runs0/out" "$work/runs1/out" \
  && ok "one run names its arms without a run number" \
  || bad "one run names its arms without a run number ($(grep ': running$' "$work/runs1/out" | tr '\n' ';'))"

# the repetitions go in order: both arms of run 1, then both arms of run 2
[ "$(grep ': running$' "$work/runs2/out")" = "nested-files/with_skill/run-1: running
nested-files/without_skill/run-1: running
nested-files/with_skill/run-2: running
nested-files/without_skill/run-2: running" ] \
  && ok "--runs 2 runs both arms of run 1 before run 2" \
  || bad "--runs 2 runs both arms of run 1 before run 2 ($(grep ': running$' "$work/runs2/out" | tr '\n' ';'))"

# a count with leading zeros is decimal, and zero is still refused
lead=""
for v in "08:x 8 runs = 48" "003:x 3 runs = 18" "010:x 10 runs = 60"; do
  dry --plugin "$with_plug" --runs "${v%%:*}" | grep -qxF "budget   : 3 eval(s) x 2 arms ${v#*:} arm calls" \
    || lead="$lead ${v%%:*}"
done
dry --plugin "$with_plug" --runs 00 >/dev/null; [ "$?" -eq 2 ] || lead="$lead 00(accepted)"
[ -z "$lead" ] && ok "--runs reads leading zeros as decimal, and 00 is no count" \
  || bad "--runs reads leading zeros as decimal, and 00 is no count (wrong:$lead)"

# one repetition that measures nothing, or cannot be graded, is that
# repetition's alone: the third session is with_skill/run-2
khook="$work/count-hook"
cat > "$khook" <<'HOOK'
#!/usr/bin/env bash
echo call >> "$HOOK_LOG"
if [ "$(wc -l < "$HOOK_LOG")" -eq 3 ]; then
  case "$KHOOK" in
    crash) exit 3;;
    lose) rm -f "$KHOOK_ARM/eval-case.json";;
  esac
fi
echo "done answer"
HOOK
chmod +x "$khook"
KHOOK=crash EV_HOOK="$khook" idrun runsx --plugin "$gitplug" --runs 2; rc=$?
xit="$(idit runsx)/nested-files"
[ "$rc" -eq 0 ] && grep -q '^nested-files/with_skill/run-2: indeterminate' "$work/runsx/out" \
  && [ "$(grep -c ': indeterminate' "$work/runsx/out")" -eq 1 ] \
  && [ "$(jq -r .outcome "$xit/with_skill/run-2/run_status.json" 2>/dev/null)" = indeterminate ] \
  && [ "$(jq -r .outcome "$xit/with_skill/run-1/run_status.json" "$xit"/without_skill/run-*/run_status.json 2>/dev/null | tr '\n' ' ')" = "ok ok ok " ] \
  && jq -e '[.runs[] | [.configuration, .run_number, .outcome]]
      == [["with_skill", 1, "ok"], ["with_skill", 2, "indeterminate"], ["without_skill", 1, "ok"], ["without_skill", 2, "ok"]]
    and .run_summary.with_skill.indeterminate_count == 1 and .run_summary.without_skill.indeterminate_count == 0
    and .metadata.runs_per_eval == 2' "$(idit runsx)/benchmark.json" >/dev/null 2>&1 \
  && ok "a repetition that measured nothing is indeterminate alone, under its run number" \
  || bad "a repetition that measured nothing is indeterminate alone, under its run number (rc $rc; $(jq -c '[.runs[] | [.configuration, .run_number, .outcome]]' "$(idit runsx)/benchmark.json" 2>&1); $(tail -n 4 "$work/runsx/out" | tr '\n' ';'))"
KHOOK=lose KHOOK_ARM="$(idit runsy)/nested-files/with_skill/run-2" EV_HOOK="$khook" idrun runsy --plugin "$gitplug" --runs 2; rc=$?
[ "$rc" -eq 2 ] && grep -qxF 'nested-files/with_skill/run-2: bin/grade failed' "$work/runsy/out" \
  && [ "$(grep -c 'bin/grade failed' "$work/runsy/out")" -eq 1 ] \
  && grep -qxF 'not recorded: nested-files/with_skill/run-2 benchmark' "$work/runsy/out" \
  && [ ! -e "$(idit runsy)/nested-files/with_skill/run-2/grading.json" ] \
  && [ -f "$(idit runsy)/nested-files/without_skill/run-2/grading.json" ] \
  && ok "a repetition that cannot be graded is named with its run number, and the rest still run" \
  || bad "a repetition that cannot be graded is named with its run number, and the rest still run (rc $rc; $(tail -n 5 "$work/runsy/out" | tr '\n' ';'))"

[ ! -s "$own_trip" ] && ok "no real agent CLI was called" || bad "no real agent CLI was called ($(cat "$own_trip"))"

exit "$fails"
