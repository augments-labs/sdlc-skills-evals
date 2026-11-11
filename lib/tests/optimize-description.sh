#!/usr/bin/env bash
# Offline test: bin/optimize-description — the train-only revision loop and
# the validation-best selection, against the FAKE adapter only.
#
# The fake's routing is driven by FAKE_ACTIVATION_HOOK: a skill fires when
# its staged description names the first word of the query, so a revised
# description changes the score the way a real one would, with zero model
# calls. The reviser is FAKE_BEHAVIORAL_HOOK: it hands back the next
# candidate from a list and records what it was shown. Real agent CLIs are
# unreachable: the tripwire shims stand first on PATH, and a call to one
# fails and is recorded.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fake_h="$here/lib/tests/fake-cli"
export SDLC_SKILLS_EVALS_ROOT="$here"
opt="$here/bin/optimize-description"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT

# the tripwire: every real CLI name records the call and fails
own_trip="$work/tripwire.log"
PATH="$here/lib/tests/tripwire:$PATH"; export PATH

# --- a synthetic plugin with the skill in both trees -------------------------

skill_md() { # $1 description — a SKILL.md with that description
  cat <<MD
---
name: probe
description: "$1"
---

# Probe

PROBE-BODY-MARKER: route here when the task names one of the words above.
MD
}

plug="$work/plugin"
mkdir -p "$plug/skills/common/probe" "$plug/plugins/sdlc-skills/skills/probe"
skill_md "covers alpha" > "$plug/skills/common/probe/SKILL.md"
skill_md "covers alpha" > "$plug/plugins/sdlc-skills/skills/probe/SKILL.md"
git -C "$plug" init -q
git -C "$plug" add -A
git -C "$plug" -c user.name=t -c user.email=t@example.invalid commit -q -m seed
plug_commit="$(git -C "$plug" rev-parse HEAD)"

# train: three positives and a negative; validation: two positives and a
# negative. Only train failures may ever reach the reviser.
desc="$work/descriptions"
mkdir -p "$desc"
cat > "$desc/probe.json" <<'JSON'
[
 {"query":"alpha task for the probe","should_trigger":true,"split":"train"},
 {"query":"beta task for the probe","should_trigger":true,"split":"train"},
 {"query":"gamma task for the probe","should_trigger":true,"split":"train"},
 {"query":"omega task elsewhere","should_trigger":false,"split":"train","expect":"other"},
 {"query":"delta check for the probe","should_trigger":true,"split":"validation"},
 {"query":"epsilon check for the probe","should_trigger":true,"split":"validation"},
 {"query":"zeta check elsewhere","should_trigger":false,"split":"validation","expect":"other"}
]
JSON
validation_strings=("delta check" "epsilon check" "zeta check")

# routing: fire probe when the staged description names the query's first
# word; record the description the OTHER tree carried at that moment
tree_log="$work/tree.log"
act_hook="$work/activation-hook"
cat > "$act_hook" <<HOOK
#!/usr/bin/env bash
plug="\$1"; q="\$2"
d="\$(sed -n 's/^description: *//p' "\$plug/skills/common/probe/SKILL.md" | head -1 | tr -d '"')"
o="\$(sed -n 's/^description: *//p' "\$plug/plugins/sdlc-skills/skills/probe/SKILL.md" | head -1 | tr -d '"')"
printf '%s|%s\n' "\$d" "\$o" >> "$tree_log"
# DEAD=validation|all: those runs read as a provider refusal (INCONCLUSIVE)
case "\${DEAD:-}:\$q" in validation:*" check "*|all:*) echo "usage limit exceeded"; exit 0;; esac
# LOCK_DIR: the workspace turns unwritable while the round is scored
[ -z "\${LOCK_DIR:-}" ] || chmod a-w "\$LOCK_DIR"
w="\${q%% *}"
case " \$d " in *" \$w "*) echo probe;; esac
HOOK
chmod +x "$act_hook"

# the reviser: call n hands back line n of \$CANDIDATES, into the file the
# prompt names; it records whether the credential seed reached its home
rev_hook="$work/reviser-hook"
cat > "$rev_hook" <<'HOOK'
#!/usr/bin/env bash
workdir="$1"
n="$(( $(wc -l < "$REVISER_CALLS" 2>/dev/null || echo 0) + 1 ))"
printf 'call %s seeded=%s\n' "$n" "$([ -f "$HOME/.fakerc" ] && echo yes || echo no)" >> "$REVISER_CALLS"
cand="$(sed -n "${n}p" "$CANDIDATES")"
case "${REVISER_MODE:-file}" in
  file) printf '%s\n' "$cand" > "$workdir/candidate-description.txt"; echo "wrote the file";;
  stdout) printf '%s\n' "$cand";;
  raw) cat "$CANDIDATE_RAW" > "$workdir/candidate-description.txt";;
  silent) exit 1;;
  stdout-fail) printf '%s\n' "$cand"; exit 3;;
esac
HOOK
chmod +x "$rev_hook"

outer_home="$work/outer-home"
mkdir -p "$outer_home/.config/sdlc-skills-evals/credentials/fake"
printf 'token\n' > "$outer_home/.config/sdlc-skills-evals/credentials/fake/.fakerc"

# one run of the optimizer, fully offline; $1 a tag naming its files
run_opt() { # $1 tag, rest: optimizer args
  local tag="$1"; shift
  mkdir -p "$work/$tag"
  : > "$work/$tag/calls"
  HOME="$outer_home" DESCRIPTIONS_ROOT="$desc" WORKSPACES_ROOT="$work/$tag/ws" \
  SDLC_SKILLS_ROOT="$plug" TRIPWIRE_LOG="$own_trip" \
  FAKE_ACTIVATION_HOOK="$act_hook" FAKE_BEHAVIORAL_HOOK="$rev_hook" \
  FAKE_RECORD_DIR="$work/$tag/rec" FAKE_SOURCE_LOG="$work/$tag/source.log" \
  FAKE_LAUNCH_LOG="$work/$tag/launch.log" \
  REVISER_CALLS="$work/$tag/calls" CANDIDATES="$work/$tag/candidates" \
    "$opt" --harness fake --harness-dir "$fake_h" --skill probe \
      --runs 1 --jobs 1 --timeout 20 --no-fixture "$@" >"$work/$tag/out" 2>&1
}

[ -x "$opt" ] && ok "bin/optimize-description is executable" \
  || bad "bin/optimize-description is executable"

# --- the dry run: the budget, and nothing launched ---------------------------

dry_out="$(HOME="$outer_home" DESCRIPTIONS_ROOT="$desc" SDLC_SKILLS_ROOT="$plug" \
  FAKE_SOURCE_LOG="$work/dry-source.log" FAKE_LAUNCH_LOG="$work/dry-launch.log" \
  TRIPWIRE_LOG="$own_trip" \
  "$opt" --harness fake --harness-dir "$fake_h" --skill probe --plugin "$plug_commit" \
    --runs 2 --max-iterations 3 --dry-run 2>&1)"
rc="$?"
[ "$rc" -eq 0 ] && ok "the dry run exits 0" || bad "the dry run exits 0 (got $rc: $dry_out)"
# 3 iterations x 7 queries x 2 runs + 2 reviser calls
grep -qE '(^|[^0-9])44 (calls|invocations)' <<< "$dry_out" \
  && ok "the dry run prices K*N*runs + (K-1) calls" \
  || bad "the dry run prices K*N*runs + (K-1) calls (got '$dry_out')"
grep -qF "$plug_commit" <<< "$dry_out" \
  && ok "the dry run names the pin" || bad "the dry run names the pin"
grep -q '^command  : bin/optimize-description --harness fake --skill probe' <<< "$dry_out" \
  && ok "the dry run names the command" || bad "the dry run names the command"
money_re='(\$[0-9])|(\bUSD\b)|(\bEUR\b)|(\bGBP\b)|(€)|(£)'
if grep -qE "$money_re" < <(printf '%s\n' "$dry_out" "$("$opt" --help 2>&1)"); then
  bad "the help and the dry run carry no monetary figure"
else
  ok "the help and the dry run carry no monetary figure"
fi
[ ! -s "$work/dry-launch.log" ] && [ ! -s "$work/dry-source.log" ] \
  && ok "the dry run sources and launches nothing" \
  || bad "the dry run sources and launches nothing"
HOME="$outer_home" DESCRIPTIONS_ROOT="$desc" TRIPWIRE_LOG="$own_trip" \
  "$opt" --harness claude-code --skill probe --plugin "$plug_commit" --dry-run >/dev/null 2>&1
[ ! -s "$own_trip" ] && ok "a real harness's dry run reaches no CLI" \
  || bad "a real harness's dry run reaches no CLI ($(cat "$own_trip"))"

# --- the loop: three iterations, the middle one best -------------------------
#
# it-1 "covers alpha"                      train 2/4, validation 1/3
# it-2 "covers alpha beta delta epsilon"   train 3/4, validation 3/3
# it-3 "covers alpha beta gamma zeta"      train 4/4, validation 0/3
#       (zeta is a validation NEGATIVE and now fires; delta and epsilon
#       miss). Train is clean, so the loop stops there, short of K=5.

mkdir -p "$work/main"
printf '%s\n' "covers alpha beta delta epsilon" "covers alpha beta gamma zeta" \
  "never used" > "$work/main/candidates"
(
  export TMPDIR="$work/outer-tmp"; mkdir -p "$TMPDIR"
  run_opt main --plugin "$plug_commit" --max-iterations 5 --campaign c1
  printf '%s\n' "$?" > "$work/main/rc"
)
ws="$work/main/ws/c1"
rc="$(cat "$work/main/rc")"
[ "$rc" -eq 0 ] && ok "the loop exits 0" || bad "the loop exits 0 (got $rc: $(tail -5 "$work/main/out"))"
for i in 1 2 3; do
  for f in description.txt results.json metrics.json; do
    [ -s "$ws/iteration-$i/$f" ] || { bad "iteration-$i/$f is written"; continue 2; }
  done
  ok "iteration-$i writes description, results and metrics"
done
[ -e "$ws/iteration-3" ] && [ ! -e "$ws/iteration-4" ] && ok "the loop stops when train has no failure" \
  || bad "the loop stops when train has no failure"
[ "$(cat "$ws/iteration-1/description.txt")" = "covers alpha" ] \
  && [ "$(cat "$ws/iteration-2/description.txt")" = "covers alpha beta delta epsilon" ] \
  && ok "each iteration records the description it scored" \
  || bad "each iteration records the description it scored"

m1="$ws/iteration-1/metrics.json"
if jq -e '.train.passed == 2 and .train.failed == 2 and .train.inconclusive == 0
          and .train.total == 4 and .train.pass_rate == 0.5
          and .validation.passed == 1 and .validation.failed == 2
          and .validation.total == 3 and ((.validation.pass_rate * 100 | round) == 33)' \
     "$m1" >/dev/null 2>&1; then
  ok "metrics count train and validation apart"
else
  bad "metrics count train and validation apart (got $(cat "$m1" 2>/dev/null))"
fi
jq -e '.validation.pass_rate == 1 and .train.pass_rate == 0.75' "$ws/iteration-2/metrics.json" >/dev/null 2>&1 \
  && jq -e '.validation.pass_rate == 0 and .train.pass_rate == 1' "$ws/iteration-3/metrics.json" >/dev/null 2>&1 \
  && ok "a revised description changes the score" \
  || bad "a revised description changes the score"
jq -e 'length == 7 and all(.[]; has("split") and has("verdict"))' "$ws/iteration-1/results.json" >/dev/null 2>&1 \
  && ok "results hold every scored query" || bad "results hold every scored query"

# selection: iteration-2 beats iteration-3
[ "$(cat "$ws/best-description.txt" 2>/dev/null)" = "covers alpha beta delta epsilon" ] \
  && ok "the best validation iteration wins, not the last" \
  || bad "the best validation iteration wins, not the last (got '$(cat "$ws/best-description.txt" 2>/dev/null)')"
jq -e '.best_iteration == 2 and (.iterations | length) == 3' "$ws/optimization.json" >/dev/null 2>&1 \
  && ok "optimization.json names the winning iteration" \
  || bad "optimization.json names the winning iteration"
grep -q 'iteration' "$ws/optimization.md" 2>/dev/null \
  && ok "optimization.md is written" || bad "optimization.md is written"

# the staged tree, both copies, carried each candidate
grep -qx 'covers alpha beta delta epsilon|covers alpha beta delta epsilon' "$tree_log" 2>/dev/null \
  && ok "the candidate is written into both staged trees" \
  || bad "the candidate is written into both staged trees"
# ...and the plugin itself is untouched
grep -q '^description: "covers alpha"$' "$plug/skills/common/probe/SKILL.md" \
  && [ -z "$(git -C "$plug" status --porcelain)" ] \
  && ok "the pinned plugin is never written" || bad "the pinned plugin is never written"

# the reviser: two calls, each shown the body, the description and the
# train failures — and never a validation query, verdict or count
[ "$(wc -l < "$work/main/calls")" -eq 2 ] && ok "the reviser runs between iterations only" \
  || bad "the reviser runs between iterations only ($(wc -l < "$work/main/calls") calls)"
p1="$work/main/rec/call-1/prompt.txt"
if [ -s "$p1" ] && grep -q 'PROBE-BODY-MARKER' "$p1" && grep -qF 'covers alpha' "$p1" \
   && grep -qF 'beta task for the probe' "$p1" && grep -qF 'gamma task for the probe' "$p1" \
   && grep -qF 'candidate-description.txt' "$p1"; then
  ok "the reviser sees the body, the description and the train failures"
else
  bad "the reviser sees the body, the description and the train failures"
fi
leak=""
ls "$work"/main/rec/call-*/prompt.txt >/dev/null 2>&1 || leak=" (no prompt was recorded)"
for pf in "$work"/main/rec/call-*/prompt.txt; do
  for v in "${validation_strings[@]}"; do grep -qF "$v" "$pf" && leak="$leak $v"; done
  grep -qiE 'validation|held.?out|holdout' "$pf" && leak="$leak (the word)"
  grep -qF 'alpha task for the probe' "$pf" && leak="$leak (a passing query)"
  grep -qF 'omega task elsewhere' "$pf" && leak="$leak (a passing query)"
done 2>/dev/null
[ -z "$leak" ] && ok "no validation query, verdict or count reaches the reviser" \
  || bad "no validation query, verdict or count reaches the reviser (leaked:$leak)"

# the reviser's isolation: a throwaway home under the outer TMPDIR, the
# credential seed resolved from the operator's home, and the adapter bound
# at source time to the operator's home — then all of it removed
env1="$work/main/rec/call-1/env"
r_home="$(sed -n 's/^HOME=//p' "$env1" 2>/dev/null)"
case "$r_home" in
  "$work/outer-tmp/sdlc-skills-evals/"*/home) ok "the reviser runs in a throwaway home under the outer TMPDIR";;
  *) bad "the reviser runs in a throwaway home under the outer TMPDIR (HOME='$r_home')";;
esac
grep -qx "LAB_CREDENTIAL_SEED=$outer_home/.config/sdlc-skills-evals/credentials" "$env1" 2>/dev/null \
  && ok "the credential seed is exported from the operator's home" \
  || bad "the credential seed is exported from the operator's home"
grep -q 'seeded=yes' "$work/main/calls" && ok "the reviser's home holds the seeded credential" \
  || bad "the reviser's home holds the seeded credential"
grep -qx "source_home=$outer_home" "$env1" 2>/dev/null \
  && ! grep -q . < <(grep -v "home=$outer_home\$" "$work/main/source.log") \
  && ok "the adapter is sourced against the operator's home, never the throwaway one" \
  || bad "the adapter is sourced against the operator's home, never the throwaway one"
grep -q '^install $' "$work/main/launch.log" \
  && ok "the reviser installs no plugin (skill-free)" \
  || bad "the reviser installs no plugin (skill-free)"
left="$(find "$work/outer-tmp" -mindepth 1 -maxdepth 2 2>/dev/null | grep -v '/sdlc-skills-evals$' | head -3)"
[ -n "$r_home" ] && [ ! -e "$(dirname "$r_home")" ] && [ -z "$left" ] \
  && ok "no run_base is left behind (TMPDIR exported)" \
  || bad "no run_base is left behind (TMPDIR exported; left: $left)"

# the same loop with TMPDIR unset: the reviser's base is under /tmp, and
# is still removed
mkdir -p "$work/unset"
printf '%s\n' "covers alpha beta gamma" > "$work/unset/candidates"
( unset TMPDIR; run_opt unset --plugin "$plug_commit" --max-iterations 2 --campaign c2
  printf '%s\n' "$?" > "$work/unset/rc" )
u_home="$(sed -n 's/^HOME=//p' "$work/unset/rec/call-1/env" 2>/dev/null)"
case "$u_home" in
  /tmp/sdlc-skills-evals/*/home) ok "with TMPDIR unset the reviser's home is under /tmp";;
  *) bad "with TMPDIR unset the reviser's home is under /tmp (HOME='$u_home')";;
esac
[ "$(cat "$work/unset/rc")" -eq 0 ] && [ -n "$u_home" ] && [ ! -e "$(dirname "$u_home")" ] \
  && [ ! -e "/tmp/$(basename "$(dirname "$u_home")")" ] \
  && ok "no run_base is left behind (TMPDIR unset)" \
  || bad "no run_base is left behind (TMPDIR unset)"
[ -s "$work/unset/ws/c2/iteration-2/metrics.json" ] \
  && ok "the second iteration runs with TMPDIR unset" \
  || bad "the second iteration runs with TMPDIR unset"

# an explicitly exported seed is the one the reviser gets
mkdir -p "$work/seed/fake" "$work/exp"
printf 'other\n' > "$work/seed/fake/.fakerc"
printf '%s\n' "covers alpha beta" > "$work/exp/candidates"
( export TMPDIR="$work/outer-tmp"; export LAB_CREDENTIAL_SEED="$work/seed"
  run_opt exp --plugin "$plug_commit" --max-iterations 2 --campaign c3 )
grep -qx "LAB_CREDENTIAL_SEED=$work/seed" "$work/exp/rec/call-1/env" 2>/dev/null \
  && ok "an exported credential seed is kept" || bad "an exported credential seed is kept"

# --- early stop: a description that already passes train --------------------
mkdir -p "$work/early"
skill_md "covers alpha beta gamma" > "$work/early-skill.md"
early_plug="$work/early-plug"
mkdir -p "$early_plug/skills/common/probe" "$early_plug/plugins/sdlc-skills/skills/probe"
cp "$work/early-skill.md" "$early_plug/skills/common/probe/SKILL.md"
cp "$work/early-skill.md" "$early_plug/plugins/sdlc-skills/skills/probe/SKILL.md"
git -C "$early_plug" init -q
: > "$work/early/candidates"
( export TMPDIR="$work/outer-tmp"; run_opt early --plugin "$early_plug" --max-iterations 5 --campaign c4 )
[ -s "$work/early/ws/c4/iteration-1/metrics.json" ] && [ ! -e "$work/early/ws/c4/iteration-2" ] \
  && [ ! -s "$work/early/calls" ] \
  && ok "zero train failures stops after the first iteration, with no reviser call" \
  || bad "zero train failures stops after the first iteration, with no reviser call"

# --- the stream fallback: no file, the answer in the stream ------------------
mkdir -p "$work/fallback"
printf '%s\n' "covers alpha beta gamma" > "$work/fallback/candidates"
( export TMPDIR="$work/outer-tmp" REVISER_MODE=stdout
  run_opt fallback --plugin "$plug_commit" --max-iterations 2 --campaign c5 )
[ "$(cat "$work/fallback/ws/c5/iteration-2/description.txt" 2>/dev/null)" = "covers alpha beta gamma" ] \
  && ok "a candidate only in the stream is read from it" \
  || bad "a candidate only in the stream is read from it"

# --- candidates that are refused ---------------------------------------------
reject_case() { # $1 tag $2 label — the candidate in $work/$1/raw
  ( export TMPDIR="$work/outer-tmp" REVISER_MODE=raw CANDIDATE_RAW="$work/$1/raw"
    run_opt "$1" --plugin "$plug_commit" --max-iterations 3 --campaign "c-$1"
    printf '%s\n' "$?" > "$work/$1/rc" )
  local w="$work/$1/ws/c-$1"
  if [ ! -e "$w/iteration-2" ] && jq -e '.stop_reason | test("rejected")' "$w/optimization.json" >/dev/null 2>&1 \
     && [ "$(cat "$w/best-description.txt" 2>/dev/null)" = "covers alpha" ]; then
    ok "$2"
  else
    bad "$2 (rc $(cat "$work/$1/rc" 2>/dev/null); $(jq -c '.stop_reason' "$w/optimization.json" 2>/dev/null))"
  fi
}
mkdir -p "$work/r-empty" "$work/r-long" "$work/r-tag" "$work/r-lines"
: > "$work/r-empty/raw"
head -c 1025 /dev/zero | tr '\0' 'a' > "$work/r-long/raw"
printf 'covers alpha <beta> gamma\n' > "$work/r-tag/raw"
printf 'covers alpha\nbeta: gamma\n' > "$work/r-lines/raw"
for t in r-empty r-long r-tag r-lines; do : > "$work/$t/candidates"; done
reject_case r-empty "an empty candidate is refused"
reject_case r-long "a candidate over 1024 characters is refused"
reject_case r-tag "a candidate carrying < or > is refused"
reject_case r-lines "a multi-line candidate is refused"
# exactly 1024 characters is allowed
mkdir -p "$work/r-max"; : > "$work/r-max/candidates"
{ printf 'covers alpha beta gamma '; head -c 1000 /dev/zero | tr '\0' 'b'; } > "$work/r-max/raw"
( export TMPDIR="$work/outer-tmp" REVISER_MODE=raw CANDIDATE_RAW="$work/r-max/raw"
  run_opt r-max --plugin "$plug_commit" --max-iterations 2 --campaign c-max )
[ "$(wc -c < "$work/r-max/ws/c-max/iteration-2/description.txt" 2>/dev/null | tr -d ' ')" -ge 1024 ] \
  && ok "a 1024-character candidate is accepted" || bad "a 1024-character candidate is accepted"

# a reviser that answers nothing stops the loop, it is not a candidate
mkdir -p "$work/silent"; : > "$work/silent/candidates"
( export TMPDIR="$work/outer-tmp" REVISER_MODE=silent
  run_opt silent --plugin "$plug_commit" --max-iterations 3 --campaign c6 )
[ ! -e "$work/silent/ws/c6/iteration-2" ] \
  && jq -e '.stop_reason | length > 0' "$work/silent/ws/c6/optimization.json" >/dev/null 2>&1 \
  && ok "a silent reviser stops the loop with a reason" \
  || bad "a silent reviser stops the loop with a reason"
jq -e '.stop_reason | test("exited 1")' "$work/silent/ws/c6/optimization.json" >/dev/null 2>&1 \
  && ok "the stop reason names the reviser's exit code" \
  || bad "the stop reason names the reviser's exit code (got $(jq -c '.stop_reason' "$work/silent/ws/c6/optimization.json" 2>/dev/null))"

# a reviser that failed is not read from its stream, whatever it printed
mkdir -p "$work/failed"
printf '%s\n' "covers alpha beta gamma" > "$work/failed/candidates"
( export TMPDIR="$work/outer-tmp" REVISER_MODE=stdout-fail
  run_opt failed --plugin "$plug_commit" --max-iterations 3 --campaign c6b )
[ ! -e "$work/failed/ws/c6b/iteration-2" ] \
  && jq -e '.stop_reason | test("exited 3")' "$work/failed/ws/c6b/optimization.json" >/dev/null 2>&1 \
  && ok "a failed reviser's stream is never taken as a candidate" \
  || bad "a failed reviser's stream is never taken as a candidate"

# --- --apply -----------------------------------------------------------------
apply_plug="$work/apply-plug"
cp -r "$plug" "$apply_plug"
mkdir -p "$work/apply"
printf '%s\n' "covers alpha beta gamma" > "$work/apply/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt apply --plugin "$apply_plug" --max-iterations 2 --campaign c7 --apply
  printf '%s\n' "$?" > "$work/apply/rc" )
want_line='description: "covers alpha beta gamma"'
if [ "$(cat "$work/apply/rc")" -eq 0 ] \
   && grep -qxF "$want_line" "$apply_plug/skills/common/probe/SKILL.md" \
   && grep -qxF "$want_line" "$apply_plug/plugins/sdlc-skills/skills/probe/SKILL.md" \
   && grep -qx 'name: probe' "$apply_plug/skills/common/probe/SKILL.md" \
   && grep -q 'PROBE-BODY-MARKER' "$apply_plug/plugins/sdlc-skills/skills/probe/SKILL.md"; then
  ok "--apply writes the winner into both trees of a directory plugin"
else
  bad "--apply writes the winner into both trees of a directory plugin (rc $(cat "$work/apply/rc"))"
fi
applied="$apply_plug/skills/common/probe/SKILL.md"
[ "$(sed -n 1p "$applied")" = "---" ] && [ "$(sed -n 2p "$applied")" = "name: probe" ] \
  && [ "$(sed -n 3p "$applied")" = "$want_line" ] && [ "$(sed -n 4p "$applied")" = "---" ] \
  && [ "$(wc -l < "$applied")" -eq "$(skill_md x | wc -l)" ] \
  && ok "--apply keeps the frontmatter's shape" || bad "--apply keeps the frontmatter's shape"

mkdir -p "$work/apply-ref"; : > "$work/apply-ref/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt apply-ref --plugin "$plug_commit" --max-iterations 2 --campaign c8 --apply
  printf '%s\n' "$?" > "$work/apply-ref/rc" )
[ "$(cat "$work/apply-ref/rc")" -eq 2 ] && [ ! -s "$work/apply-ref/launch.log" ] \
  && ok "--apply on a commit ref exits 2 before any launch" \
  || bad "--apply on a commit ref exits 2 before any launch (rc $(cat "$work/apply-ref/rc"))"

mkdir -p "$work/apply-none"; : > "$work/apply-none/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt apply-none --max-iterations 2 --campaign c9 --apply
  printf '%s\n' "$?" > "$work/apply-none/rc" )
[ "$(cat "$work/apply-none/rc")" -eq 2 ] && ok "--apply with no --plugin exits 2" \
  || bad "--apply with no --plugin exits 2 (rc $(cat "$work/apply-none/rc"))"

ro_plug="$work/ro-plug"
cp -r "$plug" "$ro_plug"; chmod -R a-w "$ro_plug"
mkdir -p "$work/apply-ro"; : > "$work/apply-ro/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt apply-ro --plugin "$ro_plug" --max-iterations 2 --campaign c10 --apply
  printf '%s\n' "$?" > "$work/apply-ro/rc" )
chmod -R u+w "$ro_plug"
[ "$(cat "$work/apply-ro/rc")" -eq 2 ] && [ ! -s "$work/apply-ro/launch.log" ] \
  && ok "--apply on an unwritable directory exits 2 before any launch" \
  || bad "--apply on an unwritable directory exits 2 before any launch (rc $(cat "$work/apply-ro/rc"))"

# --apply takes the selected iteration, not the last one
g1_plug="$work/g1-plug"; cp -r "$plug" "$g1_plug"
mkdir -p "$work/g1"
printf '%s\n' "covers alpha beta delta epsilon" "covers alpha beta gamma zeta" > "$work/g1/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt g1 --plugin "$g1_plug" --max-iterations 5 --campaign c11 --apply
  printf '%s\n' "$?" > "$work/g1/rc" )
[ "$(cat "$work/g1/rc")" -eq 0 ] \
  && grep -qxF 'description: "covers alpha beta delta epsilon"' "$g1_plug/skills/common/probe/SKILL.md" \
  && grep -qxF 'description: "covers alpha beta delta epsilon"' "$g1_plug/plugins/sdlc-skills/skills/probe/SKILL.md" \
  && ok "--apply writes an earlier winning iteration, not the last" \
  || bad "--apply writes an earlier winning iteration, not the last (rc $(cat "$work/g1/rc"))"

# --- the cap and the tie-breaks ----------------------------------------------
# it-1 "covers alpha" train 2/4; it-2 "covers alpha beta" and it-3 "covers
# beta alpha" both train 3/4, all three validation 1/3: train beats it-1,
# then the earlier of two equal lengths wins
mkdir -p "$work/cap"
printf '%s\n' "covers alpha beta" "covers beta alpha" "never used" > "$work/cap/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt cap --plugin "$plug_commit" --max-iterations 3 --campaign c12
  printf '%s\n' "$?" > "$work/cap/rc" )
cj="$work/cap/ws/c12/optimization.json"
[ "$(cat "$work/cap/rc")" -eq 0 ] && [ -e "$work/cap/ws/c12/iteration-3" ] \
  && [ ! -e "$work/cap/ws/c12/iteration-4" ] && [ "$(wc -l < "$work/cap/calls")" -eq 2 ] \
  && jq -e '(.iterations | length) == 3 and .stop_reason == "reached --max-iterations 3"' "$cj" >/dev/null 2>&1 \
  && ok "--max-iterations caps the rounds at K, with K-1 reviser calls" \
  || bad "--max-iterations caps the rounds at K, with K-1 reviser calls ($(jq -c '.stop_reason' "$cj" 2>/dev/null))"
jq -e '.best_iteration == 2' "$cj" >/dev/null 2>&1 \
  && ok "a validation tie goes to the higher train rate, then the earlier iteration" \
  || bad "a validation tie goes to the higher train rate, then the earlier iteration (got $(jq -c '.best_iteration' "$cj" 2>/dev/null))"
# it-2 "covers alpha beta xx" and it-3 "covers alpha beta" score alike:
# the shorter wins, though it came later
mkdir -p "$work/short"
printf '%s\n' "covers alpha beta xx" "covers alpha beta" > "$work/short/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt short --plugin "$plug_commit" --max-iterations 3 --campaign c13 )
jq -e '.best_iteration == 3' "$work/short/ws/c13/optimization.json" >/dev/null 2>&1 \
  && ok "a tie on both rates goes to the shorter description" \
  || bad "a tie on both rates goes to the shorter description (got $(jq -c '.best_iteration' "$work/short/ws/c13/optimization.json" 2>/dev/null))"

# --- no validation signal: nothing is selected or applied --------------------
nv_plug="$work/nv-plug"; cp -r "$plug" "$nv_plug"
mkdir -p "$work/nv"
printf '%s\n' "covers alpha beta" > "$work/nv/candidates"
( export TMPDIR="$work/outer-tmp" DEAD=validation
  run_opt nv --plugin "$nv_plug" --max-iterations 2 --campaign c14 --apply
  printf '%s\n' "$?" > "$work/nv/rc" )
nj="$work/nv/ws/c14/optimization.json"
[ "$(cat "$work/nv/rc")" -eq 2 ] \
  && jq -e '.outcome == "indeterminate" and .best_iteration == null and .applied == false
            and (.iterations | length) == 2' "$nj" >/dev/null 2>&1 \
  && [ ! -e "$work/nv/ws/c14/best-description.txt" ] \
  && cmp -s "$plug/skills/common/probe/SKILL.md" "$nv_plug/skills/common/probe/SKILL.md" \
  && ok "no validation signal selects nothing, applies nothing, and exits 2" \
  || bad "no validation signal selects nothing, applies nothing, and exits 2 (rc $(cat "$work/nv/rc"); $(jq -c '{outcome,best_iteration,applied}' "$nj" 2>/dev/null))"
mkdir -p "$work/dead"; : > "$work/dead/candidates"
( export TMPDIR="$work/outer-tmp" DEAD=all
  run_opt dead --plugin "$plug_commit" --max-iterations 3 --campaign c15
  printf '%s\n' "$?" > "$work/dead/rc" )
[ "$(cat "$work/dead/rc")" -eq 2 ] && [ ! -s "$work/dead/calls" ] \
  && jq -e '(.stop_reason | test("train scored nothing")) and .outcome == "indeterminate"' \
       "$work/dead/ws/c15/optimization.json" >/dev/null 2>&1 \
  && ok "a round with every run refused stops, unselected, with no reviser call" \
  || bad "a round with every run refused stops, unselected, with no reviser call (rc $(cat "$work/dead/rc"))"

# --- the records are written before --apply touches the plugin ---------------
lk_plug="$work/lk-plug"; cp -r "$plug" "$lk_plug"
mkdir -p "$work/lk"; : > "$work/lk/candidates"
( export TMPDIR="$work/outer-tmp" LOCK_DIR="$work/lk/ws/c16"
  run_opt lk --plugin "$lk_plug" --max-iterations 1 --campaign c16 --apply
  printf '%s\n' "$?" > "$work/lk/rc" )
chmod u+w "$work/lk/ws/c16" 2>/dev/null
[ "$(cat "$work/lk/rc")" -eq 2 ] \
  && cmp -s "$plug/skills/common/probe/SKILL.md" "$lk_plug/skills/common/probe/SKILL.md" \
  && ok "a record that cannot be written exits 2 before --apply" \
  || bad "a record that cannot be written exits 2 before --apply (rc $(cat "$work/lk/rc"))"

# --- the whole description key: folded, literal, plain, unquoted -------------
body_tail() { printf '\n# Probe\n\nPROBE-BODY-MARKER: route here when the task names one of the words above.\n'; }
key_case() { # $1 tag $2 label $3 expected description line; frontmatter lines on stdin
  local p="$work/$1-plug" fm
  fm="$(cat)"
  mkdir -p "$p/skills/common/probe" "$p/plugins/sdlc-skills/skills/probe" "$work/$1"
  { printf -- '---\nname: probe\n%s\nlicense: MIT\n---\n' "$fm"; body_tail; } > "$p/skills/common/probe/SKILL.md"
  cp "$p/skills/common/probe/SKILL.md" "$p/plugins/sdlc-skills/skills/probe/SKILL.md"
  : > "$work/$1/candidates"
  ( export TMPDIR="$work/outer-tmp"
    run_opt "$1" --plugin "$p" --max-iterations 1 --campaign "c-$1" --apply
    printf '%s\n' "$?" > "$work/$1/rc" )
  local want="$work/$1/want"
  { printf -- '---\nname: probe\n%s\nlicense: MIT\n---\n' "$3"; body_tail; } > "$want"
  if [ "$(cat "$work/$1/rc")" -eq 0 ] && cmp -s "$want" "$p/skills/common/probe/SKILL.md" \
     && cmp -s "$want" "$p/plugins/sdlc-skills/skills/probe/SKILL.md"; then
    ok "$2"
  else
    bad "$2 (rc $(cat "$work/$1/rc"); got: $(sed -n '2,6p' "$p/skills/common/probe/SKILL.md" | tr '\n' '|'))"
  fi
}
key_case k-folded "a folded description is read whole and replaced whole" \
  'description: "covers alpha beta"' <<'FM'
description: >-
  covers alpha
  beta
FM
[ "$(cat "$work/k-folded/ws/c-k-folded/iteration-1/description.txt" 2>/dev/null)" = "covers alpha beta" ] \
  && ok "a folded description is scored as its joined text" \
  || bad "a folded description is scored as its joined text"
key_case k-literal "a literal block description keeps its line break, escaped" \
  'description: "covers alpha\nbeta"' <<'FM'
description: |
  covers alpha
  beta
FM
key_case k-plain "a plain multi-line description is read whole and replaced whole" \
  'description: "covers alpha beta"' <<'FM'
description: covers alpha
  beta
FM
key_case k-unquoted "an unquoted one-line description is replaced quoted" \
  'description: "covers alpha"' <<'FM'
description: covers alpha
FM

# a copy with no description key is refused before any launch
nk="$work/nk-plug"
mkdir -p "$nk/skills/common/probe" "$nk/plugins/sdlc-skills/skills/probe" "$work/nk"
skill_md "covers alpha" > "$nk/skills/common/probe/SKILL.md"
{ printf -- '---\nname: probe\n---\n'; body_tail; } > "$nk/plugins/sdlc-skills/skills/probe/SKILL.md"
: > "$work/nk/candidates"
( export TMPDIR="$work/outer-tmp"
  run_opt nk --plugin "$nk" --max-iterations 1 --campaign c-nk
  printf '%s\n' "$?" > "$work/nk/rc" )
[ "$(cat "$work/nk/rc")" -eq 2 ] && ! grep -q '^activation' "$work/nk/launch.log" 2>/dev/null \
  && ok "a SKILL.md copy with no description key exits 2 before any launch" \
  || bad "a SKILL.md copy with no description key exits 2 before any launch (rc $(cat "$work/nk/rc"))"

# --- refusals ----------------------------------------------------------------
dry() { HOME="$outer_home" DESCRIPTIONS_ROOT="$desc" SDLC_SKILLS_ROOT="$plug" TRIPWIRE_LOG="$own_trip" \
  "$opt" --harness fake --harness-dir "$fake_h" --plugin "$plug_commit" --dry-run "$@" 2>&1; }
out="$(dry --skill probe --max-iterations 00)"; rc=$?
[ "$rc" -eq 2 ] && ok "--max-iterations 00 is refused" || bad "--max-iterations 00 is refused (rc $rc: $out)"
# 3 x 7 x 8 + 2: 08 is not octal here
out="$(dry --skill probe --max-iterations 03 --runs 08)"; rc=$?
[ "$rc" -eq 0 ] && grep -qE '(^|[^0-9])170 calls' <<< "$out" \
  && ok "a zero-padded count is read as its decimal value" \
  || bad "a zero-padded count is read as its decimal value (rc $rc: $out)"
cp "$desc/probe.json" "$work/probe.json"; mkdir -p "$desc/sub"; cp "$desc/probe.json" "$desc/sub/x.json"
for s in ../probe sub/x . ..; do
  out="$(dry --skill "$s")"; rc=$?
  [ "$rc" -eq 2 ] && grep -q 'is a name' <<< "$out" \
    && ok "--skill '$s' is refused as a path" || bad "--skill '$s' is refused as a path (rc $rc: $out)"
done
rm -rf "$work/probe.json" "$desc/sub"

HOME="$outer_home" DESCRIPTIONS_ROOT="$desc" "$opt" --harness fake --harness-dir "$fake_h" \
  --skill nosuch --plugin "$plug" --dry-run >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a skill with no query set exits 2" || bad "a skill with no query set exits 2"
HOME="$outer_home" DESCRIPTIONS_ROOT="$desc" WORKSPACES_ROOT="$work/unrun" TRIPWIRE_LOG="$own_trip" \
  "$opt" --harness codex --skill probe --plugin "$plug" --max-iterations 2 >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "an unrunnable harness exits 2" || bad "an unrunnable harness exits 2"

[ ! -s "$own_trip" ] && ok "no real agent CLI was reached" \
  || bad "no real agent CLI was reached ($(cat "$own_trip"))"

exit "$fails"
