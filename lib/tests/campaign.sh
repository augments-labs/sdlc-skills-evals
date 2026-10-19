#!/usr/bin/env bash
# Offline test: bin/campaign — what it freezes, what it plans, what it
# counts, and the offline paths that must launch nothing.
#
# Every run here uses the fake harness (--harness fake, or --harness-dir
# lib/tests/fake-cli), so no agent CLI is reached and no token is spent.
# The non-launching cases put a SENTINEL real CLI on PATH — one that
# fails and records the call — and the campaign-run control that follows
# proves the sentinel is reachable at all. The live eval path is reached
# only as far as its refusals, which come before any launch.
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
jq -e --arg c "$plug_commit" '.plugin_commit == $c and .harness == "fake" and (.arms | type == "array")' \
  "$d/campaign.json" >/dev/null && ok "inputs frozen with the key set" || bad "inputs frozen with the key set"

"$here/bin/campaign" report "$l" >/dev/null 2>&1 \
  && bad "report refused before runs end" || ok "report refused before runs end"

"$here/bin/campaign" run "$l" >/dev/null 2>&1 \
  || { bad "campaign run"; exit "$fails"; }
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
SDLC_SKILLS_ROOT="$tag_repo" "$here/bin/campaign" new "$l4" --plugin selftest-campaign-tag \
  --harness fake --arms green --scenarios probe-ok --runs 1 \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d4="$(ls -d "$here"/results/*-"$l4" 2>/dev/null | head -1)"
if [ -n "$d4" ] && jq -e --arg c "$one" '.plugin_commit == $c' "$d4/campaign.json" >/dev/null 2>&1; then
  ok "the campaign froze the commit the tag named"
else
  bad "the campaign froze the commit the tag named"
fi
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
"$here/bin/campaign" --evals --harness fake --skill yagni --without old \
  --campaign "$eval_ws_live" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "the live eval path refuses --without old with no --old-plugin" \
  || bad "the live eval path refuses --without old with no --old-plugin"
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
for text in "$("$here/bin/campaign" --help 2>&1)" \
            "$("$here/bin/campaign" --evals --dry-run --harness fake --skill yagni 2>&1)"; do
  if printf '%s\n' "$text" | grep -qE "$money_re"; then
    bad "the help and the campaign preparation carry no monetary figure"
  else
    ok "the help and the campaign preparation carry no monetary figure"
  fi
done

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
