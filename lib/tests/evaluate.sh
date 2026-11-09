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

# one evaluation, fully offline; $1 a tag naming its files
run_ev() { # $1 tag, rest: evaluate args
  local tag="$1"; shift
  mkdir -p "$work/$tag"
  HOME="$outer_home" EVALS_ROOT="$evroot" WORKSPACES_ROOT="$work/$tag/ws" \
  TRIPWIRE_LOG="$own_trip" FAKE_BEHAVIORAL_HOOK="$hook" \
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

[ ! -s "$own_trip" ] && ok "no real agent CLI was called" || bad "no real agent CLI was called ($(cat "$own_trip"))"

exit "$fails"
