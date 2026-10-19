#!/usr/bin/env bash
# Offline test: bin/campaign — what it freezes, what it plans, what it
# counts, and the offline paths that must launch nothing.
#
# Almost every run here uses the FAKE adapter (--harness fake, which
# routes to lib/tests/fake-cli, or --harness-dir lib/tests/fake-cli; one
# case uses a copy of it under another name, so a harness directory
# override is observable). The exceptions, and what each of them reaches:
#
#   the preparation cases name --harness opencode and prepare without
#     sourcing an adapter at all; the FAKE_SOURCE_LOG case holds the
#     eval preparation to that.
#   the campaign-run control reaches the SENTINEL CLI on PATH — one that
#     fails and records the call — so the cases above are not vacuous.
#     The sentinel spends nothing.
#
# The live eval path is reached as far as its refusals, and once against
# the fake adapter, which is not an agent CLI. No case in this file
# reaches a real agent CLI: the sentinel stands in for one, and it always
# fails.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
export SDLC_SKILLS_EVALS_ROOT="$here"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

standin="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$standin" "$work"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
plug_commit="$(git -C "$standin" rev-parse HEAD)"

# the pin a run resolves when the caller names none
inv_commit="$(jq -r '.upstream.commit' "$here/config/upstream-inventory.json")"

l="selftest-$$"
# The eval path writes a workspace under the lab root. Every eval case
# here names its own workspace, so the test cleans up after itself and
# never leaves an iteration behind.
eval_ws_live="selftest-evalref-$$"
trap 'rm -rf "$here"/results/*-"$l" "$here"/results/*-"$l"-* "$here"/workspaces/selftest-eval*-"$$"' EXIT
"$here/bin/campaign" new "$l" --plugin "$standin" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1 \
  || { bad "campaign new"; exit "$fails"; }
d="$(ls -d "$here"/results/*-"$l")"
# the key set IS the guarantee: a campaign that loses tier, harness_dir
# or scenario_dir stops honouring them, and the plan still prints them
want_keys='["arms","created","harness","harness_dir","lab_commit","label","plugin_commit","plugin_ref","runs","scenario_dir","scenarios","suite","tier"]'
jq -e --arg c "$plug_commit" --argjson k "$want_keys" \
  '.plugin_commit == $c and .harness == "fake" and (.arms | type == "array")
   and (keys == $k)' \
  "$d/campaign.json" >/dev/null && ok "inputs frozen with the key set" || bad "inputs frozen with the key set"

# --- the run honours the directory overrides the campaign froze ---------------
#
# The plan prints them, and the run passes them, so the two cannot
# disagree. The adapter answers to another name, because the harness
# directory override is invisible under the name the runner routes by
# itself.

alt_hdir="$work/alt-harness-dir"
mkdir -p "$alt_hdir"
cp "$here/lib/tests/fake-cli/fake.sh" "$alt_hdir/altfake.sh"
l_run="selftest-runopts-$$"
"$here/bin/campaign" new "$l_run" --plugin "$standin" --harness altfake --arms green \
  --scenarios probe-ok --runs 1 --harness-dir "$alt_hdir" \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
out="$("$here/bin/campaign" run "$l_run" 2>&1)"
printf '%s' "$out" | grep -q "completed 1/1 runs" \
  && ok "the run honours the directories the campaign froze" \
  || bad "the run honours the directories the campaign froze (got '$out')"
rm -rf "$here"/results/*-"$l_run"

"$here/bin/campaign" report "$l" >/dev/null 2>&1 \
  && bad "report refused before runs end" || ok "report refused before runs end"

"$here/bin/campaign" run "$l" >/dev/null 2>&1 \
  || { bad "campaign run"; exit "$fails"; }
# the run adds the attempt's count, and adds nothing else
run_keys='["arms","created","harness","harness_dir","lab_commit","label","last_run","plugin_commit","plugin_ref","runs","scenario_dir","scenarios","suite","tier"]'
jq -e --argjson k "$run_keys" 'keys == $k' "$d/campaign.json" >/dev/null \
  && ok "the record keeps the key set after the run" || bad "the record keeps the key set after the run"
"$here/bin/campaign" report "$l" >/dev/null 2>&1 \
  || { bad "campaign report"; exit "$fails"; }
grep -q "^## Commit" "$d/summary.md" && ok "summary has Commit" || bad "summary has Commit"
grep -q "^## Behavior scenarios" "$d/summary.md" && ok "summary has Behavior scenarios" || bad "summary has Behavior scenarios"
grep -q "^## Costs" "$d/summary.md" && ok "summary has Costs" || bad "summary has Costs"
grep -q "probe-ok" "$d/summary.md" && ok "summary names the scenario" || bad "summary names the scenario"

# a manifest-less probe scenario cannot go green, even in a campaign
l2="selftest-nochecks-$$"
"$here/bin/campaign" new "$l2" --plugin "$standin" --harness fake --arms green \
  --scenarios probe-nochecks --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d2="$(ls -d "$here"/results/*-"$l2")"
"$here/bin/campaign" run "$l2" >/dev/null 2>&1
jq -e '.verdict == "indeterminate" and .stage == "checks"' "$d2/runs/probe-nochecks-green-1.json" >/dev/null \
  && ok "campaign records indeterminate, never false green" || bad "campaign records indeterminate, never false green"
rm -rf "$here"/results/*-"$l2"

# --- the pin a campaign freezes ----------------------------------------------
#
# A campaign with no --plugin freezes the committed upstream commit, and
# names the exact invocations it plans.

l3="selftest-pin-$$"
out="$("$here/bin/campaign" new "$l3" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
d3="$(ls -d "$here"/results/*-"$l3" 2>/dev/null | head -1)"
if [ -n "$d3" ] && jq -e --arg c "$inv_commit" '.plugin_commit == $c and .plugin_ref == $c' \
    "$d3/campaign.json" >/dev/null 2>&1; then
  ok "a campaign with no --plugin freezes the committed pin"
else
  bad "a campaign with no --plugin freezes the committed pin"
fi
printf '%s' "$out" | grep -qF "pin        : $inv_commit" \
  && ok "the campaign names the pin it froze" || bad "the campaign names the pin it froze"
printf '%s' "$out" | grep -qF "command    : bin/behavior --harness fake --scenario probe-ok --arm green --plugin $inv_commit" \
  && ok "the campaign names the exact planned invocations" \
  || bad "the campaign names the exact planned invocations"
# the plan is the whole command, option by option: a prefix match would
# let a plan that drops --record or a directory override pass
plan_cmd="$(printf '%s\n' "$out" | sed -n 's/^command    : //p' | head -1)"
d3="$(ls -d "$here"/results/*-"$l3" 2>/dev/null | head -1)"
want="bin/behavior --harness fake --scenario probe-ok --arm green --plugin $inv_commit --record $d3 --scenario-dir $here/lib/tests/fake-cli/scenarios"
[ "$plan_cmd" = "$want" ] \
  && ok "the campaign names the whole planned invocation" \
  || bad "the campaign names the whole planned invocation (got '$plan_cmd')"
rm -rf "$here"/results/*-"$l3"

# --- the plan names EVERY option the run honours -----------------------------
#
# The expectation is built from the whole option set the live path passes
# to bin/behavior — not from the subset this campaign happens to use — so
# that dropping any one of them turns this case red. A plan that names
# no --tier, no --harness-dir or no --base measures a different campaign
# from the one that was prepared, and a user who copies the printed
# invocation gets that difference.

plan_base="$work/planbase"
mkdir -p "$plan_base"
git -C "$plan_base" init -q
git -C "$plan_base" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
plan_base_commit="$(git -C "$plan_base" rev-parse HEAD)"
l_plan="selftest-plan-$$"
out="$("$here/bin/campaign" new "$l_plan" --plugin "$standin" --harness fake \
  --arms green,red --base "$plan_base_commit" --scenarios probe-ok --runs 1 \
  --tier small --harness-dir "$here/lib/tests/fake-cli" \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
d_plan="$(ls -d "$here"/results/*-"$l_plan" 2>/dev/null | head -1)"
plan_green="$(printf '%s\n' "$out" | sed -n 's/^command    : //p' | grep -- "--arm green" | head -1)"
plan_red="$(printf '%s\n' "$out" | sed -n 's/^command    : //p' | grep -- "--arm red" | head -1)"
want_green="bin/behavior --harness fake --scenario probe-ok --arm green --plugin $standin --tier small --record $d_plan --harness-dir $here/lib/tests/fake-cli --scenario-dir $here/lib/tests/fake-cli/scenarios"
want_red="bin/behavior --harness fake --scenario probe-ok --arm red --base $plan_base_commit --tier small --record $d_plan --harness-dir $here/lib/tests/fake-cli --scenario-dir $here/lib/tests/fake-cli/scenarios"
[ "$plan_green" = "$want_green" ] \
  && ok "the green arm's plan names every option the run honours" \
  || bad "the green arm's plan names every option the run honours (got '$plan_green')"
[ "$plan_red" = "$want_red" ] \
  && ok "the red arm's plan names every option the run honours" \
  || bad "the red arm's plan names every option the run honours (got '$plan_red')"
rm -rf "$here"/results/*-"$l_plan"

# --- the run asks for the tier the campaign froze ----------------------------
#
# The tier is frozen in campaign.json and printed in the plan, but a
# campaign that froze --tier small and a run that asked for something
# else measure different campaigns, and nothing would say so. The
# adapter records the tier it was handed, so the frozen value and the
# value the run asked for are compared — not two hardcoded strings.

l_tier="selftest-tier-$$"
"$here/bin/campaign" new "$l_tier" --plugin "$standin" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --tier small \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d_tier="$(ls -d "$here"/results/*-"$l_tier" 2>/dev/null | head -1)"
frozen_tier="$(jq -r '.tier // empty' "$d_tier/campaign.json" 2>/dev/null)"
tier_log="$work/tier.log"
rm -f "$tier_log"
FAKE_LAUNCH_LOG="$tier_log" "$here/bin/campaign" run "$l_tier" >/dev/null 2>&1
tier_asked="$(sed -n 's/^tier //p' "$tier_log" 2>/dev/null | head -1)"
if [ "$frozen_tier" = small ] && [ "$tier_asked" = "$frozen_tier" ]; then
  ok "the run asks for the tier the campaign froze"
else
  bad "the run asks for the tier the campaign froze (froze '$frozen_tier', asked '$tier_asked')"
fi
rm -rf "$here"/results/*-"$l_tier"

# --- a tier the adapter cannot set is refused, not run at the default -------
#
# The runner must refuse a run that asks for a tier the adapter cannot
# set, rather than running the default model and calling it that tier.
# FAKE_NO_TIER=1 makes the double bind no tier at all, the way an
# adapter that cannot set one does.

out="$(FAKE_NO_TIER=1 "$here/bin/behavior" --harness fake --scenario probe-ok --arm green \
  --plugin "$standin" --tier small --harness-dir "$here/lib/tests/fake-cli" \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
rc="$?"
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF "binds no tiers"; then
  ok "the runner refuses a tier the adapter cannot set"
else
  bad "the runner refuses a tier the adapter cannot set (exit $rc, got '$out')"
fi

# and the campaign that froze that tier measures nothing, saying so
l_notier="selftest-notier-$$"
"$here/bin/campaign" new "$l_notier" --plugin "$standin" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --tier small \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d_notier="$(ls -d "$here"/results/*-"$l_notier" 2>/dev/null | head -1)"
out="$(FAKE_NO_TIER=1 "$here/bin/campaign" run "$l_notier" 2>&1)"
if printf '%s' "$out" | grep -q "completed 0/1 runs"; then
  ok "a campaign whose adapter cannot set the tier measures nothing"
else
  bad "a campaign whose adapter cannot set the tier measures nothing (got '$out')"
fi
if [ -n "$d_notier" ] && [ -z "$(find "$d_notier/runs" -name '*.json' 2>/dev/null | head -1)" ]; then
  ok "the refused run wrote no record"
else
  bad "the refused run wrote no record"
fi
rm -rf "$here"/results/*-"$l_notier"

# --- a campaign runs the commit it froze, not a tag that moved ---------------
#
# A tag may be named when the campaign is prepared; the commit it names is
# frozen, and the run uses that commit — a tag that moves between the two
# cannot become the pin of the run.

tag_repo="$work/tags"
mkdir -p "$tag_repo"
git -C "$tag_repo" init -q
git -C "$tag_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
one="$(git -C "$tag_repo" rev-parse HEAD)"
git -C "$tag_repo" tag selftest-campaign-tag
git -C "$tag_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
two="$(git -C "$tag_repo" rev-parse HEAD)"
l4="selftest-tag-$$"
out="$(SDLC_SKILLS_ROOT="$tag_repo" "$here/bin/campaign" new "$l4" --plugin selftest-campaign-tag \
  --harness fake --arms green --scenarios probe-ok --runs 1 \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
d4="$(ls -d "$here"/results/*-"$l4" 2>/dev/null | head -1)"
if [ -n "$d4" ] && jq -e --arg c "$one" '.plugin_commit == $c' "$d4/campaign.json" >/dev/null 2>&1; then
  ok "the campaign froze the commit the tag named"
else
  bad "the campaign froze the commit the tag named"
fi
# the plan carries the COMMIT the ref named, not the ref: a ref that
# moves after the campaign was prepared cannot become what the run
# installs
tag_plan="$(printf '%s\n' "$out" | sed -n 's/^command    : //p' | head -1)"
case "$tag_plan" in
  *"--plugin $one"*) ok "the campaign's plan carries the commit a ref names";;
  *) bad "the campaign's plan carries the commit a ref names (got '$tag_plan')";;
esac
case "$tag_plan" in
  *"--plugin selftest-campaign-tag"*) bad "the campaign's plan carries the commit, not the ref";;
  *) ok "the campaign's plan carries the commit, not the ref";;
esac
git -C "$tag_repo" tag -f selftest-campaign-tag "$two" >/dev/null 2>&1
SDLC_SKILLS_ROOT="$tag_repo" "$here/bin/campaign" run "$l4" >/dev/null 2>&1
if [ -n "$d4" ] && jq -e --arg c "$one" '.plugin_commit == $c' \
    "$d4/runs/probe-ok-green-1.json" >/dev/null 2>&1; then
  ok "the run used the frozen commit, not the moved tag"
else
  bad "the run used the frozen commit, not the moved tag"
fi
rm -rf "$here"/results/*-"$l4"

# --- a directory plugin: the plan, the run and the record agree -------------
#
# A directory is the operator's own working tree and is used as it is, so
# the campaign plans the PATH, the run runs that path, and the commit the
# record carries is the commit that tree is at.

plugdir="$work/plugdir"
mkdir -p "$plugdir"
git -C "$plugdir" init -q
git -C "$plugdir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m tree
plug_head="$(git -C "$plugdir" rev-parse HEAD)"
l6="selftest-dir-$$"
out="$("$here/bin/campaign" new "$l6" --plugin "$plugdir" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
d6="$(ls -d "$here"/results/*-"$l6" 2>/dev/null | head -1)"
printf '%s' "$out" | grep -qF "pin        : $plugdir" \
  && ok "the campaign names the tree it freezes" || bad "the campaign names the tree it freezes"
printf '%s' "$out" | grep -qF "command    : bin/behavior --harness fake --scenario probe-ok --arm green --plugin $plugdir" \
  && ok "the campaign plans the path a directory plugin installs" \
  || bad "the campaign plans the path a directory plugin installs"
if [ -n "$d6" ] && jq -e --arg c "$plug_head" '.plugin_commit == $c' \
    "$d6/campaign.json" >/dev/null 2>&1; then
  ok "the campaign froze the commit the tree is at"
else
  bad "the campaign froze the commit the tree is at"
fi
"$here/bin/campaign" run "$l6" >/dev/null 2>&1
if [ -n "$d6" ] && jq -e --arg c "$plug_head" '.plugin_commit == $c and .verdict == "pass"' \
    "$d6/runs/probe-ok-green-1.json" >/dev/null 2>&1; then
  ok "the run recorded the commit the tree is at"
else
  bad "the run recorded the commit the tree is at"
fi
rm -rf "$here"/results/*-"$l6"

# --- a completion is a completion -------------------------------------------
#
# A run that produced no record measured nothing, and the line that
# announces the campaign's completion must mean what it says.

l7="selftest-norecord-$$"
empty_root="$work/empty-root"
mkdir -p "$empty_root"
git -C "$empty_root" init -q
"$here/bin/campaign" new "$l7" --harness fake --arms green --scenarios probe-ok --runs 1 \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
out="$(SDLC_SKILLS_ROOT="$empty_root" "$here/bin/campaign" run "$l7" 2>&1)"
printf '%s' "$out" | grep -q "completed 0/1 runs" \
  && ok "a run that produced no record is not counted as complete" \
  || bad "a run that produced no record is not counted as complete"
rm -rf "$here"/results/*-"$l7"

# --- a completion is this run's completion ----------------------------------
#
# The count is over the records THIS run wrote, and the report's pending
# gate reads the same count, so a stale record from an earlier attempt can
# never stand in for a missing observation.

l8="selftest-twice-$$"
"$here/bin/campaign" new "$l8" --plugin "$standin" --harness fake --arms green --scenarios probe-ok --runs 1 \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
out="$("$here/bin/campaign" run "$l8" 2>&1)"
printf '%s' "$out" | grep -q "completed 1/1 runs" \
  && ok "the first run counts its own record" || bad "the first run counts its own record (got '$out')"
out="$("$here/bin/campaign" run "$l8" 2>&1)"
printf '%s' "$out" | grep -q "completed 1/1 runs" \
  && ok "a second run counts only its own records" \
  || bad "a second run counts only its own records (got '$out')"
rm -rf "$here"/results/*-"$l8"

# a second attempt that measured nothing must not be satisfied by the
# first attempt's record
l9="selftest-stale-$$"
stale_dir="$work/stale"
mkdir -p "$stale_dir"
git -C "$stale_dir" init -q
git -C "$stale_dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m tree
"$here/bin/campaign" new "$l9" --plugin "$stale_dir" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d9="$(ls -d "$here"/results/*-"$l9" 2>/dev/null | head -1)"
"$here/bin/campaign" run "$l9" >/dev/null 2>&1
[ -n "$d9" ] && [ "$(find "$d9/runs" -name '*.json' | wc -l)" -eq 1 ] \
  && ok "the first attempt wrote a record" || bad "the first attempt wrote a record"
rm -rf "$stale_dir"
out="$("$here/bin/campaign" run "$l9" 2>&1)"
printf '%s' "$out" | grep -q "completed 0/1 runs" \
  && ok "the second attempt counts no record" || bad "the second attempt counts no record (got '$out')"
if "$here/bin/campaign" report "$l9" >/dev/null 2>&1; then
  bad "the report refuses when the newest attempt wrote no record"
else
  ok "the report refuses when the newest attempt wrote no record"
fi
rm -rf "$here"/results/*-"$l9"

# --- the campaign's provenance line -----------------------------------------
#
# The record must name the tree the runs measured. The line is keyed to
# the records that measured a plugin — the green arm's — so a red arm's
# base commit is never presented as a plugin commit.

prov_dir="$work/prov"
base_dir="$work/base"
mkdir -p "$prov_dir" "$base_dir"
git -C "$prov_dir" init -q
git -C "$prov_dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
prov_one="$(git -C "$prov_dir" rev-parse HEAD)"
git -C "$base_dir" init -q
git -C "$base_dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
base_one="$(git -C "$base_dir" rev-parse HEAD)"
l10="selftest-prov-$$"
"$here/bin/campaign" new "$l10" --plugin "$prov_dir" --harness fake --arms green,red \
  --base "$base_one" --scenarios probe-ok --runs 1 \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d10="$(ls -d "$here"/results/*-"$l10" 2>/dev/null | head -1)"
# the plugin tree moves after the campaign was prepared
git -C "$prov_dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
prov_two="$(git -C "$prov_dir" rev-parse HEAD)"
SDLC_SKILLS_ROOT="$base_dir" "$here/bin/campaign" run "$l10" >/dev/null 2>&1
# the arms are isolated on the TREE, not only on the record's field: the
# green arm measures the plugin tree, the red arm the base's tree
arms_log="$work/arms-install.log"
rm -f "$arms_log"
SDLC_SKILLS_ROOT="$base_dir" FAKE_LAUNCH_LOG="$arms_log" \
  "$here/bin/campaign" run "$l10" >/dev/null 2>&1
green_install="$(sed -n 's/^install //p' "$arms_log" 2>/dev/null | sed -n 1p)"
red_install="$(sed -n 's/^install //p' "$arms_log" 2>/dev/null | sed -n 2p)"
green_head="$(sed -n 's/^install-head //p' "$arms_log" 2>/dev/null | sed -n 1p)"
red_head="$(sed -n 's/^install-head //p' "$arms_log" 2>/dev/null | sed -n 2p)"
if [ "$green_install" = "$prov_dir" ] && [ "$green_head" = "$prov_two" ]; then
  ok "the green arm installs the tree the campaign names"
else
  bad "the green arm installs the tree the campaign names (installed '$green_install' at '$green_head')"
fi
if [ -n "$red_install" ] && [ "$red_head" = "$base_one" ] \
   && [ "$red_install" != "$green_install" ] && [ "$red_head" != "$green_head" ]; then
  ok "the red arm installs the base's tree, not the green arm's"
else
  bad "the red arm installs the base's tree, not the green arm's (installed '$red_install' at '$red_head')"
fi
if [ -n "$d10" ] && "$here/bin/campaign" report "$l10" >/dev/null 2>&1; then
  grep -q "plugin commit measured: $prov_two" "$d10/summary.md" \
    && ok "the summary names the commit the green arm measured" \
    || bad "the summary names the commit the green arm measured"
  grep -q "($prov_one)" "$d10/summary.md" \
    && ok "the summary still names the commit the campaign froze" \
    || bad "the summary still names the commit the campaign froze"
  if grep -q "$base_one" "$d10/summary.md"; then
    bad "the summary does not name the red arm's base commit as a plugin commit"
  else
    ok "the summary does not name the red arm's base commit as a plugin commit"
  fi
else
  bad "the summary names the commit the green arm measured (no summary)"
fi
rm -rf "$here"/results/*-"$l10"

# a campaign whose tree did not move names no measured commit
l11="selftest-prov2-$$"
still_dir="$work/still"
mkdir -p "$still_dir"
git -C "$still_dir" init -q
git -C "$still_dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m tree
"$here/bin/campaign" new "$l11" --plugin "$still_dir" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d11="$(ls -d "$here"/results/*-"$l11" 2>/dev/null | head -1)"
"$here/bin/campaign" run "$l11" >/dev/null 2>&1
"$here/bin/campaign" report "$l11" >/dev/null 2>&1
if [ -n "$d11" ] && grep -q "plugin commit measured" "$d11/summary.md"; then
  bad "the summary names no measured commit when the tree did not move"
else
  ok "the summary names no measured commit when the tree did not move"
fi
rm -rf "$here"/results/*-"$l11"

# --- the campaign's none arm -------------------------------------------------
#
# The none arm loads no skills: its planned command carries no --plugin,
# and it produces a record of its own.

l12="selftest-none-$$"
out="$("$here/bin/campaign" new "$l12" --plugin "$standin" --harness fake --arms green,none \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
d12="$(ls -d "$here"/results/*-"$l12" 2>/dev/null | head -1)"
case "$out" in
  *"--arm none"*) ok "the plan names the none arm";;
  *) bad "the plan names the none arm";;
esac
none_line="$(printf '%s\n' "$out" | sed -n 's/^command    : //p' | grep -- "--arm none" | head -1)"
case "$none_line" in
  *--plugin*) bad "the none arm's planned command carries no --plugin";;
  *) ok "the none arm's planned command carries no --plugin";;
esac
out="$("$here/bin/campaign" run "$l12" 2>&1)"
printf '%s' "$out" | grep -q "completed 2/2 runs" \
  && ok "both arms produced a record" || bad "both arms produced a record (got '$out')"
if [ -n "$d12" ] && [ -f "$d12/runs/probe-ok-none-1.json" ]; then
  ok "the none arm produced a record"
else
  bad "the none arm produced a record"
fi
rm -rf "$here"/results/*-"$l12"

# --- the eval dry run names every option the live path honours --------------

out="$("$here/bin/campaign" --evals --dry-run --harness fake --all \
  --harness-dir "$here/lib/tests/fake-cli" --timeout 600 2>&1)"
printf '%s' "$out" | grep -qF -- "--harness-dir $here/lib/tests/fake-cli" \
  && ok "the eval dry run names the harness directory" \
  || bad "the eval dry run names the harness directory"
printf '%s' "$out" | grep -qF -- "--timeout 600" \
  && ok "the eval dry run names the timeout" || bad "the eval dry run names the timeout"

# the eval dry run's command is the whole command
eval_cmd="$(printf '%s\n' "$out" | sed -n 's/^command    : //p')"
want="bin/campaign --evals --plugin $inv_commit --harness fake --all --without none --timeout 600 --harness-dir $here/lib/tests/fake-cli"
[ "$eval_cmd" = "$want" ] \
  && ok "the eval dry run names the whole planned invocation" \
  || bad "the eval dry run names the whole planned invocation (got '$eval_cmd')"

# --- the eval dry run names the tree it installs -----------------------------
#
# A ref moves. The eval preparation plan resolves it once and its command
# carries the commit it named, so a tag that moves afterwards cannot change
# what the plan installs. The plan is compared against a REF, not against
# the default pin: where the ref and the tree are the same string, the two
# behaviours cannot be told apart.

eval_tag_repo="$work/evaltags"
mkdir -p "$eval_tag_repo"
git -C "$eval_tag_repo" init -q
git -C "$eval_tag_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
eval_one="$(git -C "$eval_tag_repo" rev-parse HEAD)"
git -C "$eval_tag_repo" tag selftest-eval-tag
git -C "$eval_tag_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
eval_two="$(git -C "$eval_tag_repo" rev-parse HEAD)"
eval_ws="selftest-evalws-$$"
out="$(SDLC_SKILLS_ROOT="$eval_tag_repo" "$here/bin/campaign" --evals --dry-run \
  --harness fake --harness-dir "$here/lib/tests/fake-cli" --skill yagni \
  --plugin selftest-eval-tag --campaign "$eval_ws" 2>&1)"
printf '%s' "$out" | grep -qF "pin        : $eval_one" \
  && ok "the eval dry run names the commit a ref resolves to" \
  || bad "the eval dry run names the commit a ref resolves to"
eval_cmd="$(printf '%s\n' "$out" | sed -n 's/^command    : //p')"
case "$eval_cmd" in
  *"--plugin $eval_one"*) ok "the eval planned command carries the commit, not the ref";;
  *) bad "the eval planned command carries the commit, not the ref (got '$eval_cmd')";;
esac
# the tag moves: the run still installs the commit the plan named
git -C "$eval_tag_repo" tag -f selftest-eval-tag "$eval_two" >/dev/null 2>&1
eval_launch="$work/evallaunch.log"
rm -f "$eval_launch"
( cd "$here" && SDLC_SKILLS_ROOT="$eval_tag_repo" FAKE_LAUNCH_LOG="$eval_launch" \
    eval "$eval_cmd" ) >/dev/null 2>&1
eval_install="$(sed -n 's/^install //p' "$eval_launch" 2>/dev/null | head -1)"
eval_head="$(sed -n 's/^install-head //p' "$eval_launch" 2>/dev/null | head -1)"
if [ -n "$eval_install" ] && [ "$eval_head" = "$eval_one" ]; then
  ok "the eval run installs the commit the plan named, not the moved tag"
else
  bad "the eval run installs the commit the plan named, not the moved tag (installed '$eval_install' at '$eval_head')"
fi
rm -rf "$here/workspaces/$eval_ws"

# --- the eval live path launches a redirecting adapter ------------------------
#
# Every real adapter (harnesses/*.sh) redirects the launch's stderr to
# "$errlog", and the fake double does the same. A campaign that launches
# without setting errlog aborts the LAUNCH under `set -u`: the CLI is
# never called, the arm's stream stays empty, and the campaign still
# reports the eval as graded — a run that measured nothing, reported as
# a measurement.
#
# So the eval path is run LIVE against the redirecting double, and the
# launch must REACH the CLI: the arm's stream carries what the double
# emitted. The tree is a stand-in checkout the plugin is pinned from, so
# no upstream checkout and no network call are needed.

eval_live_repo="$work/evallive"
mkdir -p "$eval_live_repo"
git -C "$eval_live_repo" init -q
git -C "$eval_live_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
eval_live_commit="$(git -C "$eval_live_repo" rev-parse HEAD)"
eval_live_ws="selftest-evallive-$$"
eval_live_log="$work/evallive.log"
rm -f "$eval_live_log"
# the double keeps the real adapters' redirect: without it, the case
# below would prove nothing about a real harness
redirect_probe="$work/redirect.errlog"
rm -f "$redirect_probe"
bash -c 'set -uo pipefail; source "$1"; timeout_s=3; errlog="$2"; adapter_run_behavioral /tmp /tmp /tmp' \
  _ "$here/lib/tests/fake-cli/fake.sh" "$redirect_probe" >/dev/null 2>&1
if [ -f "$redirect_probe" ]; then
  ok "the double keeps the real adapters' stderr redirect"
else
  bad "the double keeps the real adapters' stderr redirect (the launch wrote no errlog)"
fi
# a private TMPDIR, so the launch's own temporary files are observable
eval_live_tmp="$work/evallive-tmp"
mkdir -p "$eval_live_tmp"
eval_live_out="$(TMPDIR="$eval_live_tmp" SDLC_SKILLS_ROOT="$eval_live_repo" FAKE_LAUNCH_LOG="$eval_live_log" \
  "$here/bin/campaign" --evals --harness fake --harness-dir "$here/lib/tests/fake-cli" \
  --plugin "$eval_live_commit" --skill yagni --campaign "$eval_live_ws" 2>&1)"
eval_live_rc="$?"
if [ "$eval_live_rc" -eq 0 ]; then
  ok "the eval live path completes against a redirecting adapter"
else
  bad "the eval live path completes against a redirecting adapter (exit $eval_live_rc, got '$eval_live_out')"
fi
# the launch REACHED the CLI: the arm's stream carries what the double
# emitted. An empty stream means the launch never ran.
eval_live_stream=""
for s in "$here/workspaces/$eval_live_ws"/*/*/*/stream.jsonl; do
  [ -s "$s" ] && { eval_live_stream="$s"; break; }
done
if [ -n "$eval_live_stream" ]; then
  ok "the eval live path launches through the redirecting adapter"
else
  bad "the eval live path launches through the redirecting adapter (the launch never ran: no stream content)"
fi
case "$eval_live_out" in
  *"unbound variable"*) bad "the eval live path launches with errlog set";;
  *) ok "the eval live path launches with errlog set";;
esac
# the campaign reports the launch's own status: a launch that died
# before the CLI was called is not a run that exited 0
case "$eval_live_out" in
  *"run exit 0"*) ok "the eval live path reports a successful run";;
  *) bad "the eval live path reports a successful run (got '$eval_live_out')";;
esac
# the launch's temporary files are removed on every exit path: the
# errlog the redirect writes to must not outlive the campaign
if [ -z "$(find "$eval_live_tmp" -maxdepth 1 -name 'tmp.*' -type f 2>/dev/null | head -1)" ]; then
  ok "the eval live path leaves no launch file behind"
else
  bad "the eval live path leaves no launch file behind (a temporary file survived)"
fi
rm -rf "$here/workspaces/$eval_live_ws"

# --- the live eval path stops before any launch ------------------------------
#
# The eval path spends tokens, so its offline cases stop at the refusals
# that come first: the default pin it cannot resolve, and the old arm it
# was not given.

out="$(SDLC_SKILLS_ROOT="$empty_root" "$here/bin/campaign" --evals --harness fake --skill yagni \
  --campaign "$eval_ws_live" 2>&1)"
rc="$?"
[ "$rc" -eq 2 ] && ok "the live eval path refuses a default pin it cannot resolve" \
  || bad "the live eval path refuses a default pin it cannot resolve (exit $rc)"
printf '%s' "$out" | grep -qF "$inv_commit" \
  && ok "the refusal names the committed pin" || bad "the refusal names the committed pin"
out="$("$here/bin/campaign" --evals --harness fake --skill yagni --without old \
  --campaign "$eval_ws_live" 2>&1)"
rc="$?"
# the refusal NAMES the missing option: an exit 2 alone would be
# satisfied by any later refusal
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF -- "--old-plugin"; then
  ok "the live eval path refuses --without old with no --old-plugin"
else
  bad "the live eval path refuses --without old with no --old-plugin (exit $rc, got '$out')"
fi
rm -rf "$here/workspaces/$eval_ws_live"

# --- a campaign with no usable pin refuses -----------------------------------
#
# An inventory that names no commit is refused by BOTH campaign paths, and
# NO tree is named in its place: the campaign falls back to nothing, never
# to some other tree.

broken_inv="$work/no-commit-inventory.json"
jq '.upstream.commit = "v11.0.0"' "$here/config/upstream-inventory.json" > "$broken_inv"
out="$(INVENTORY_PATH="$broken_inv" "$here/bin/campaign" --evals --harness fake --skill yagni \
  --campaign "$eval_ws_live" 2>&1)"
rc="$?"
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF "no usable upstream pin"; then
  ok "the eval path refuses a default pin it cannot resolve"
else
  bad "the eval path refuses a default pin it cannot resolve (exit $rc, got '$out')"
fi
case "$out" in
  *"pin        :"*) bad "the eval refusal names no tree in place of the pin";;
  *) ok "the eval refusal names no tree in place of the pin";;
esac
l_nopin="selftest-nopin-$$"
out="$(INVENTORY_PATH="$broken_inv" "$here/bin/campaign" new "$l_nopin" --harness fake \
  --arms green --scenarios probe-ok --runs 1 \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
rc="$?"
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF "no usable upstream pin"; then
  ok "a campaign with no usable pin refuses"
else
  bad "a campaign with no usable pin refuses (exit $rc, got '$out')"
fi
case "$out" in
  *"pin        :"*) bad "the campaign refusal names no tree in place of the pin";;
  *) ok "the campaign refusal names no tree in place of the pin";;
esac
if ls -d "$here"/results/*-"$l_nopin" >/dev/null 2>&1; then
  bad "the refusal prepared no campaign"
else
  ok "the refusal prepared no campaign"
fi
rm -rf "$here"/results/*-"$l_nopin" "$here/workspaces/$eval_ws_live"

# --- no invented monetary cost ----------------------------------------------
#
# The offline paths report the plan, never a price. The pattern is a
# currency symbol followed by a digit, or a three-letter currency code —
# the pricing LANGUAGE the help carries ("billed to your own harness
# account") is not a figure and is not matched.

money_re='(\$[0-9])|(\bUSD\b)|(\bEUR\b)|(\bGBP\b)|(€)|(£)'
# The help and the preparation are checked apart: one label for two
# texts would let a figure in either of them pass unnoticed.
if printf '%s\n' "$("$here/bin/campaign" --help 2>&1)" | grep -qE "$money_re"; then
  bad "the help carries no monetary figure"
else
  ok "the help carries no monetary figure"
fi
if printf '%s\n' "$("$here/bin/campaign" --evals --dry-run --harness fake --skill yagni 2>&1)" \
    | grep -qE "$money_re"; then
  bad "the campaign preparation carries no monetary figure"
else
  ok "the campaign preparation carries no monetary figure"
fi

# --- the non-launching paths -------------------------------------------------
#
# A sentinel real CLI stands on PATH: it fails and records that it was
# called. The help and the campaign preparation must never reach it.

sentinel_log="$work/sentinel.log"
sentinel_dir="$work/sentinel"
mkdir -p "$sentinel_dir"
for cli in opencode claude codex kimi; do
  cat >"$sentinel_dir/$cli" <<SENTINEL
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$sentinel_log"
exit 1
SENTINEL
  chmod +x "$sentinel_dir/$cli"
done
PATH="$sentinel_dir:$PATH"; export PATH

l5="selftest-sentinel-$$"
source_log="$work/sourced.log"
"$here/bin/campaign" --help >/dev/null 2>&1
"$here/bin/campaign" new "$l5" --harness opencode --plugin "$standin" --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
# the eval dry run, behind the sentinel twice over: with a real harness
# name, so a launch would reach the sentinel, and with the fake adapter
# directory, so a load of an adapter would leave a trace
"$here/bin/campaign" --evals --dry-run --harness opencode --skill yagni >/dev/null 2>&1
FAKE_SOURCE_LOG="$source_log" "$here/bin/campaign" --evals --dry-run --harness fake \
  --harness-dir "$here/lib/tests/fake-cli" --skill yagni >/dev/null 2>&1
[ ! -f "$sentinel_log" ] && ok "help and the campaign preparation call no CLI" \
  || bad "help and the campaign preparation call no CLI (the sentinel was called)"
[ ! -f "$source_log" ] && ok "the campaign preparation loads no adapter" \
  || bad "the campaign preparation loads no adapter (an adapter was sourced)"

# the control: the campaign RUN does reach the CLI, so the case above is
# not vacuous. The sentinel fails, so nothing is spent.
"$here/bin/campaign" run "$l5" >/dev/null 2>&1
[ -f "$sentinel_log" ] && ok "the campaign run reaches the CLI (the control)" \
  || bad "the campaign run reaches the CLI (the control)"
rm -rf "$here"/results/*-"$l5"

exit "$fails"
